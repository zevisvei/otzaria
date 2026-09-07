/// רשימת ה-URLs המאושרים גישה לרשת עבור תוספים.
///
/// ## איך מאשרים כתובת חדשה (אין צורך ב-release!)
/// מקור האמת **היחיד** הוא הקובץ `plugin_network_allowlist.txt` בשורש
/// הריפו, כפי שהוא בענף **`dev`** — האפליקציה מושכת אותו משם בזמן ריצה:
/// <https://github.com/Otzaria/otzaria/blob/dev/plugin_network_allowlist.txt>
///
/// מוסיפים את הכתובת לקובץ (שורה = קידומת URL, `#` = הערה) — האישור
/// נכנס לתוקף **מיד** אצל כל המשתמשים עם מיזוג ל-dev, בכל גרסה מותקנת.
///
/// הרשימה המקומפלת [pluginNetworkAllowlist] (גיבוי לא-מקוון) **מחוללת**
/// מאותו קובץ בכל בנייה — אין רשימה שנייה לתחזק, ואין קובץ נגיש לעריכה
/// אצל המשתמש. חוללה ידנית: `dart run tool/generate_plugin_network_allowlist.dart`.
///
/// כל ערך הוא **קידומת** (prefix) — מאושרים ה-URL עצמו וכל
/// תתי-הנתיבים תחתיו, ולא שאר הדומיין.
///
/// ## דוגמה
/// אם הרשימה מכילה: `https://github.com/Otzaria/otzaria-library`
///
/// יותרו:
/// - `https://github.com/Otzaria/otzaria-library`
/// - `https://github.com/Otzaria/otzaria-library/`
/// - `https://github.com/Otzaria/otzaria-library/releases/latest`
/// - `https://github.com/Otzaria/otzaria-library?tab=readme`
///
/// ייחסמו:
/// - `https://github.com/` (נתיב הורה)
/// - `https://github.com/Otzaria/another-repo` (נתיב אחר)
/// - `https://github.com/Otzaria/otzaria-library2` (קידומת תואמת חלקית)
///
/// ## כללים
/// - חובה לכלול scheme מלא (`https://` או `http://`).
/// - מותר לציין דומיין שלם כדי להתיר את כולו: `https://api.example.com`
///   יתיר כל URL שמתחיל ב-`https://api.example.com/`.
/// - אין להשאיר `/` סופי — הוא לא משנה את ההתנהגות אך מבלבל.
library;

export 'plugin_network_allowlist.g.dart' show pluginNetworkAllowlist;

import 'plugin_network_allowlist.g.dart';

/// דומייני ה-CDN שאליהם GitHub מפנה (redirect) בהורדת asset של release.
///
/// אינם ברשימת ההיתר הגלובלית בכוונה — אסור לאפשר אליהם גישה *ישירה*
/// (`network.fetchStream`/`network.download`), אלא רק כיעד של redirect שמקורו
/// ב-URL מורשה של GitHub Releases. ראו [isGithubReleaseRedirectAllowed].
const Set<String> _githubReleaseCdnHosts = <String>{
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// כתובות loopback מקומיות — שירותי AI מקומיים (Ollama / LM Studio) ועוד.
const Set<String> _loopbackHosts = <String>{'localhost', '127.0.0.1', '::1'};

/// בודקת האם [host] הוא כתובת loopback מקומית.
bool isLoopbackHost(String host) => _loopbackHosts.contains(host.toLowerCase());

/// מחזירה את שם ההרשאה הנדרשת לגישת רשת אל [uri]:
/// `network.localhost` ליעד loopback מקומי, אחרת `network.access`.
String requiredNetworkPermissionFor(Uri uri) =>
    isLoopbackHost(uri.host) ? 'network.localhost' : 'network.access';

/// מחזירה את הצהרת ה-loopback מתוך [allowlist] שמתירה את [uri], או `null`.
///
/// מתאימה רק כאשר [uri] עצמו הוא loopback מקומי (http/https). כל ערך הצהרה:
/// - host בלבד (`127.0.0.1` / `localhost`) — מתיר כל פורט/נתיב על אותו host.
/// - URL מלא (`http://127.0.0.1:11434`) — מתיר רק את אותו origin ונתיביו
///   (התאמת prefix רגילה, כולל פורט), כך שפורט אחר על אותו host נחסם.
String? matchingLoopbackPrefix(Uri uri, Iterable<String> allowlist) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!isLoopbackHost(uri.host)) return null;

  final requestHost = uri.host.toLowerCase();
  for (final raw in allowlist) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    if (isLoopbackHost(trimmed)) {
      if (trimmed.toLowerCase() == requestHost) return raw;
      continue;
    }
    if (matchingNetworkAllowlistPrefix(uri, <String>[trimmed]) != null) {
      return raw;
    }
  }
  return null;
}

/// מפרקת את קובץ ה-allowlist הרשמי (`plugin_network_allowlist.txt`):
/// שורה = קידומת URL אחת; שורות ריקות ושורות `#` (הערות) מדולגות.
List<String> parsePluginNetworkAllowlistText(String source) => source
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

/// בודקת האם מותר לעקוב אחרי redirect מ-[previous] אל [target].
///
/// מתירה אך ורק את התרחיש של הורדת asset מ-GitHub Releases: ה-hop הקודם
/// הוא ב-`github.com` והיעד הוא אחד מדומייני ה-CDN של גיטהאב. **חוזה:**
/// הקורא מבטיח ש-[previous] כבר אושר בעצמו (לולאת ההורדה בודקת כל hop) —
/// לכן אין כאן בדיקת allowlist נוספת עליו. מאחר שלא ניתן להגיע לדומיין
/// CDN ככתובת התחלתית, שרשרת שהגיעה ל-CDN לגיטימית רשאית להמשיך בין
/// דומייני CDN בלבד.
bool isGithubReleaseRedirectAllowed(Uri previous, Uri target) {
  if (target.scheme != 'https') return false;
  if (!_githubReleaseCdnHosts.contains(target.host.toLowerCase())) return false;

  final previousHost = previous.host.toLowerCase();
  return previousHost == 'github.com' ||
      _githubReleaseCdnHosts.contains(previousHost);
}

/// בודקת האם [uri] מורשה לגישה על-ידי תוספים.
///
/// מחזירה `true` רק אם ה-URL הוא בדיוק אחת מהקידומות ברשימה
/// [pluginNetworkAllowlist], או נתיב תחתיה (מופרד ב-`/`, `?` או `#`).
///
/// השוואת קידומת מתבצעת case-insensitive על ה-scheme וה-host
/// (תקני URI), ו-case-sensitive על הנתיב.
bool isUriAllowedForPluginNetwork(Uri uri) =>
    matchingNetworkAllowlistPrefix(uri, pluginNetworkAllowlist) != null;

/// מחזיר את ערך הקידומת הראשון שתואם ל-[uri], או `null` אם אין התאמה.
///
/// ההתאמה מתבצעת לפי אותם כללים של [isUriAllowedForPluginNetwork], אך על
/// כל רשימת קידומות נתונה. משמש הן לרשימה הגלובלית המובנית והן לרשימות
/// הצהרתיות/זמניות.
String? matchingNetworkAllowlistPrefix(Uri uri, Iterable<String> allowlist) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }

  // מנרמלים scheme + host ל-lowercase כפי שדורש תקן ה-URI,
  // ושומרים על נתיב/query/fragment כמו שהם (case-sensitive).
  final normalizedHost = uri.host.toLowerCase();
  final normalizedUrl = StringBuffer()
    ..write(uri.scheme.toLowerCase())
    ..write('://')
    ..write(normalizedHost);
  if (uri.hasPort) {
    normalizedUrl
      ..write(':')
      ..write(uri.port);
  }
  normalizedUrl.write(uri.path);
  if (uri.hasQuery) {
    normalizedUrl
      ..write('?')
      ..write(uri.query);
  }
  if (uri.hasFragment) {
    normalizedUrl
      ..write('#')
      ..write(uri.fragment);
  }
  final fullUrl = normalizedUrl.toString();

  for (final rawPrefix in allowlist) {
    // מנרמלים את הקידומת באותו אופן.
    final prefixUri = Uri.tryParse(rawPrefix);
    if (prefixUri == null) continue;
    if (prefixUri.scheme != 'http' && prefixUri.scheme != 'https') continue;

    final normalizedPrefix = StringBuffer()
      ..write(prefixUri.scheme.toLowerCase())
      ..write('://')
      ..write(prefixUri.host.toLowerCase());
    if (prefixUri.hasPort) {
      normalizedPrefix
        ..write(':')
        ..write(prefixUri.port);
    }
    normalizedPrefix.write(prefixUri.path);
    final prefix = normalizedPrefix.toString();

    if (fullUrl == prefix) return rawPrefix;
    if (fullUrl.startsWith('$prefix/')) return rawPrefix;
    if (fullUrl.startsWith('$prefix?')) return rawPrefix;
    if (fullUrl.startsWith('$prefix#')) return rawPrefix;
  }

  return null;
}
