#include "jump_list_manager.h"

#include <windows.h>

#include <objbase.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <mutex>
#include <optional>
#include <thread>

namespace {

using Microsoft::WRL::ComPtr;

std::mutex g_async_mutex;
std::optional<std::vector<std::string>> g_pending_titles;
bool g_worker_running = false;

void RunPendingUpdates() {
  for (;;) {
    std::vector<std::string> titles;
    {
      std::lock_guard<std::mutex> lock(g_async_mutex);
      if (!g_pending_titles.has_value()) {
        g_worker_running = false;
        return;
      }
      titles = std::move(*g_pending_titles);
      g_pending_titles.reset();
    }
    const HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr)) {
      jump_list::UpdateOpenTabs(titles);
      ::CoUninitialize();
    }
  }
}

// כותרת הקטגוריה ב-Jump List (מתחת ל"משימות").
const wchar_t kCategoryTitle[] = L"טאבים פתוחים";

// PKEY_Title — מוגדר מקומית במקום להסתמך על <propkey.h>, שמספק רק הצהרה
// (לא הגדרה) ללא INITGUID, ועלול להיכלל מראש דרך shell headers ולשבור את
// הקישור. ה-GUID וה-pid הם הערכים הקבועים של PKEY_Title.
const PROPERTYKEY kPropertyKeyTitle = {
    {0xF29F85E0,
     0x4FF9,
     0x1068,
     {0xAB, 0x91, 0x08, 0x00, 0x2B, 0x27, 0xB3, 0xD9}},
    2};

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), result.data(), size);
  return result;
}

// יוצר IShellLink לפריט טאב: מריץ את ה-exe הנוכחי עם
// `otzaria://open/tab/<index>`, וכותרתו להצגה נקבעת דרך PKEY_Title.
HRESULT CreateTabShellLink(int index, const std::wstring& title,
                           IShellLinkW** out_link) {
  *out_link = nullptr;

  ComPtr<IShellLinkW> link;
  HRESULT hr = ::CoCreateInstance(CLSID_ShellLink, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
  if (FAILED(hr)) {
    return hr;
  }

  wchar_t exe_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return HRESULT_FROM_WIN32(::GetLastError());
  }
  link->SetPath(exe_path);
  link->SetIconLocation(exe_path, 0);

  std::wstring arguments = L"otzaria://open/tab/" + std::to_wstring(index);
  link->SetArguments(arguments.c_str());

  // הכותרת הנראית ב-Jump List נקבעת דרך PKEY_Title על ה-IPropertyStore של
  // הקיצור — IShellLink::SetDescription לבדו אינו מספיק לפריטי קטגוריה.
  ComPtr<IPropertyStore> store;
  hr = link.As(&store);
  if (FAILED(hr)) {
    return hr;
  }

  PROPVARIANT title_value;
  hr = ::InitPropVariantFromString(title.c_str(), &title_value);
  if (FAILED(hr)) {
    return hr;
  }
  hr = store->SetValue(kPropertyKeyTitle, title_value);
  ::PropVariantClear(&title_value);
  if (FAILED(hr)) {
    return hr;
  }
  hr = store->Commit();
  if (FAILED(hr)) {
    return hr;
  }

  *out_link = link.Detach();
  return S_OK;
}

}  // namespace

bool jump_list::UpdateOpenTabs(const std::vector<std::string>& titles_utf8) {
  ComPtr<ICustomDestinationList> destination_list;
  HRESULT hr =
      ::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&destination_list));
  if (FAILED(hr)) {
    return false;
  }

  UINT max_slots = 0;
  ComPtr<IObjectArray> removed;
  hr = destination_list->BeginList(&max_slots, IID_PPV_ARGS(&removed));
  if (FAILED(hr)) {
    return false;
  }

  // רשימה ריקה — מסיימים בלי קטגוריה כדי לנקות את "טאבים פתוחים".
  if (titles_utf8.empty()) {
    return SUCCEEDED(destination_list->CommitList());
  }

  ComPtr<IObjectCollection> collection;
  hr = ::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&collection));
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  // לא מוסיפים מעבר למספר הפריטים שהמערכת מוכנה להציג — מעבר לכך
  // AppendCategory נכשל.
  size_t count = titles_utf8.size();
  if (count > max_slots) {
    count = max_slots;
  }
  for (size_t i = 0; i < count; ++i) {
    ComPtr<IShellLinkW> link;
    if (SUCCEEDED(CreateTabShellLink(static_cast<int>(i),
                                     Utf16FromUtf8(titles_utf8[i]), &link))) {
      collection->AddObject(link.Get());
    }
  }

  ComPtr<IObjectArray> items;
  hr = collection.As(&items);
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  hr = destination_list->AppendCategory(kCategoryTitle, items.Get());
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  return SUCCEEDED(destination_list->CommitList());
}

void jump_list::UpdateOpenTabsAsync(std::vector<std::string> titles_utf8) {
  std::lock_guard<std::mutex> lock(g_async_mutex);
  g_pending_titles = std::move(titles_utf8);
  if (g_worker_running) {
    return;
  }
  g_worker_running = true;
  try {
    std::thread(RunPendingUpdates).detach();
  } catch (const std::exception&) {
    // בלי thread ה-Jump List נשאר ישן; זה עדיף על עצירת ה-UI thread.
    g_worker_running = false;
    g_pending_titles.reset();
  }
}
