#ifndef RUNNER_JUMP_LIST_MANAGER_H_
#define RUNNER_JUMP_LIST_MANAGER_H_

#include <string>
#include <vector>

namespace jump_list {

// בונה מחדש את קטגוריית "טאבים פתוחים" ב-Jump List של שורת המשימות מתוך
// רשימת כותרות (UTF-8) לפי הסדר. כל פריט מריץ את אוצריא עם
// `otzaria://open/tab/<index>` (0-based). רשימה ריקה מנקה את הקטגוריה.
//
// חובה לקרוא מ-thread שאיתחל COM. מחזיר true בהצלחה.
bool UpdateOpenTabs(const std::vector<std::string>& titles_utf8);

// כמו [UpdateOpenTabs], אך על thread עובד עם STA משלו, וחוזר מיד.
//
// ⚠️ אסור להריץ את העדכון על ה-UI thread: CommitList של ה-Shell נמשך
// במחשבים מסוימים 30–180 שניות, ומאחר שה-isolate של Dart רץ על אותו thread,
// החלון הראשי לא הופיע כל אותו זמן (issue #1192). עדכון שמגיע בזמן שאחר
// רץ מחליף את הממתין — רק הרשימה האחרונה נכתבת.
void UpdateOpenTabsAsync(std::vector<std::string> titles_utf8);

}  // namespace jump_list

#endif  // RUNNER_JUMP_LIST_MANAGER_H_
