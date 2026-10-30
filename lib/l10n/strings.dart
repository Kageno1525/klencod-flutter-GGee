import 'package:flutter/material.dart';

class S {
  static Locale current = const Locale('ar');
  static bool get isAr => current.languageCode == 'ar';
  static String _(String key) => (_map[isAr ? 'ar' : 'en'] ?? {})[key] ?? key;

  static String get appName        => 'GGE'; // ✅ تم التغيير
  static String get login          => _('login');
  static String get username       => _('username');
  static String get password       => _('password');
  static String get logout         => _('logout');
  static String get connecting     => _('connecting');
  static String get loginSuccess   => _('loginSuccess');
  static String get loginFailed    => _('loginFailed');
  static String get mainTitle      => _('mainTitle');
  static String get transferTroops => _('transferTroops');
  static String get trainTroops    => _('trainTroops');
  static String get smuggleTroops  => _('smuggleTroops');
  static String get commanders     => _('commanders');
  static String get smuggleDesc    => _('smuggleDesc');
  static String get transferDesc   => _('transferDesc');
  static String get trainDesc      => _('trainDesc');
  static String get cmdDesc        => _('cmdDesc');
  static String get settings       => _('settings');
  static String get logoutConfirm  => _('logoutConfirm');
  static String get welcome        => 'مرحبا'; // ✅ تم التغيير
  static String get from           => _('from');
  static String get to             => _('to');
  static String get units          => _('units');
  static String get selectUnits    => _('selectUnits');
  static String get selectAll      => _('selectAll');
  static String get deselectAll    => _('deselectAll');
  static String get send           => _('send');
  static String get sending        => _('sending');
  static String get transferOk     => _('transferOk');
  static String get transferFail   => _('transferFail');
  static String get noUnitsSelected => _('noUnitsSelected');
  static String get loadingUnits   => _('loadingUnits');
  static String get loadUnits      => _('loadUnits');
  static String get offenseOnly    => _('offenseOnly');
  static String get defenseOnly    => _('defenseOnly');
  static String get allUnits       => _('allUnits');
  static String get total          => _('total');
  static String get available      => _('available');
  static String get amountToSend   => _('amountToSend');
  static String get sameCastleError => _('sameCastleError');
  static String get allianceMembers => _('allianceMembers');
  static String get peaceActive     => _('peaceActive');
  static String get noPeaceActive   => _('noPeaceActive');
  static String get peaceTime       => _('peaceTime');
  static String get distance        => _('distance');
  static String get clicks          => _('clicks');
  static String get selectMember    => _('selectMember');
  static String get memberCastle    => _('memberCastle');
  static String get loadingMembers  => _('loadingMembers');
  static String get noAllianceMembers => _('noAllianceMembers');
  static String get peaceOnly       => _('peaceOnly');
  static String get allMembers      => _('allMembers');
  static String get sendTo          => _('sendTo');
  static String get notInAlliance   => _('notInAlliance');
  static String get maxMovements    => _('maxMovements');
  static String get allLordsBusy    => _('allLordsBusy');
  static String get stationTime     => _('stationTime');
  static String get selectLord      => _('selectLord');
  static String get autoLord        => _('autoLord');
  static String get commanderBusy   => _('commanderBusy');
  static String get commanderFree   => _('commanderFree');
  static String get timeRemaining   => _('timeRemaining');
  static String get recall          => _('recall');
  static String get recallSuccess   => _('recallSuccess');
  static String get recallFail      => _('recallFail');
  static String get noCommanders    => _('noCommanders');
  static String get selectCastle   => _('selectCastle');
  static String get unitType       => _('unitType');
  static String get amount         => _('amount');
  static String get startTraining  => _('startTraining');
  static String get trainingOk     => _('trainingOk');
  static String get trainingFail   => _('trainingFail');
  static String get statsTitle              => _('statsTitle');
  static String get statsDesc               => _('statsDesc');
  static String get notificationsTitle      => _('notificationsTitle');
  static String get notificationsDesc       => _('notificationsDesc');
  static String get notificationsEnabled    => _('notificationsEnabled');
  static String get notificationsEnabledDesc => _('notificationsEnabledDesc');
  static String get soundAlert              => _('soundAlert');
  static String get soundAlertDesc          => _('soundAlertDesc');
  static String get noAlerts                => _('noAlerts');
  static String get noAlertsDesc            => _('noAlertsDesc');
  static String get noCastles               => _('noCastles');
  static String get delete                  => _('delete');
  static String get details                 => _('details');
  static String get deleteAll               => _('deleteAll');
  static String get deleteAlertConfirm      => _('deleteAlertConfirm');
  static String get allianceAttacks         => _('allianceAttacks');
  static String get allianceAttacksDesc     => _('allianceAttacksDesc');
  static String get attackerCastle          => _('attackerCastle');
  static String get targetCastle            => _('targetCastle');
  static String get attackingUnits          => _('attackingUnits');
  static String get defenseUnits            => _('defenseUnits');
  static String get defenseInfo             => _('defenseInfo');
  static String get defenseNotAvailable     => _('defenseNotAvailable');
  static String get defenseStat             => _('defenseStat');
  static String get perHour                 => _('perHour');
  static String get allianceMember          => _('allianceMember');
  static String get cancel   => _('cancel');
  static String get ok       => _('ok');
  static String get close    => _('close');
  static String get error    => _('error');
  static String get retry    => _('retry');
  static String get language => _('language');
  static String get none     => _('none');
  static String get refresh  => _('refresh');

  static String unitName(String? englishName) {
    if (englishName == null || englishName.isEmpty) {
      return isAr ? 'جندي مجهول' : 'Unknown unit';
    }
    if (!isAr) return englishName;

    final lower = englishName.toLowerCase().trim();
    if (_unitAr.containsKey(lower)) return _unitAr[lower]!;

    String clean = lower.replaceAll('barracks_unit_', '').replaceAll('barracks', '').replaceAll('_', '').replaceAll(' ', '').trim();
    if (_unitAr.containsKey(clean)) return _unitAr[clean]!;

    String prefix = '';
    if (clean.contains('veteran')) prefix += 'محنك ';
    if (clean.contains('relic')) prefix += 'تذكاري ';
    if (clean.contains('heavy')) prefix += 'ثقيل ';
    if (clean.contains('elite')) prefix += 'نخبة ';
    if (clean.contains('kings')) prefix += 'ملكي ';

    if (clean.contains('maceman') || clean.contains('mace')) return '${prefix}صولجان';
    if (clean.contains('spearman') || clean.contains('spear')) return '${prefix}رمح';
    if (clean.contains('swordsman') || clean.contains('sword')) return '${prefix}سياف';
    if (clean.contains('crossbowman') || clean.contains('crossbow')) return '${prefix}نابل';
    if (clean.contains('longbowman') || clean.contains('longbow')) return '${prefix}قوس طويل';
    if (clean.contains('bowman') || clean.contains('bow') || clean.contains('archer')) return '${prefix}نشاب';
    if (clean.contains('halberdier') || clean.contains('halberd')) return '${prefix}هالبرد';
    if (clean.contains('maiden')) return '${prefix}محاربة';
    if (clean.contains('north')) return 'حامي الشمال';
    if (clean.contains('valkyrie')) return '${prefix}فالكيري';
    if (clean.contains('glasswing')) return 'رامي زجاجي';
    if (clean.contains('flamebreath')) return 'مهاجم النيران المجنون';
    if (clean.contains('scalebound')) return 'حارس القشور';
    if (clean.contains('scaleshard')) return 'قناص حرشفي';

    return englishName;
  }

  static const Map<String, String> _unitAr = {
    'maceman': 'جندي بهراوة', 'spearman': 'جندي رماح', 'bowman': 'نشاب', 'crossbowman': 'نابل',
    'swordsman': 'محارب بالسيف', 'archer': 'رامي سهام', 'twohandedswordsman': 'سياف يستخدم اليدين',
    'halberdier': 'حامل الرمح والفأس', 'heavycrossbowman': 'نشاب ثقيل', 'longbowman': 'نابل ذو قوس طويل',
    'veteranhalberdier': 'جندي رماح وفئوس محنك', 'veterantwohandedswordsman': 'سياف محنك يستخدم اليدين',
    'veteranlongbowman': 'نابل قوس طويل محنك', 'veteranheavycrossbowman': 'نشاب ثقيل محنك',
    'relicaxeman': 'حامل الفأس التذكاري', 'relicshortbowman': 'نبال الأتر التذكاري',
    'relichammerman': 'حامل مطرقة الأثار', 'reliclongbowman': 'رام الاثار',
    'shieldmaiden': 'المحاربة', 'protectorofthenorth': 'حامي الشمال',
    'valkyrieranger': 'رامي فالكيري', 'valkyriesniper': 'قناص فالكيري',
    'glasswingarcher': 'رامي زجاجي', 'flamebreathberserker': 'مهاجم النيران المجنون',
    'scaleboundguardian': 'حارس القشور', 'scaleshardmarksman': 'قناص حرشفي',
    'mace': 'صولجان', 'spear': 'رمح', 'sword': 'سياف', 'halberd': 'هالبرد', 'axe': 'فأس',
    'pikeman': 'رمح طويل', 'twohandedsword': 'سياف بيدين', 'heavycrossbow': 'قوس مستعرض ثقيل',
    'heavyspearman': 'رمح ثقيل', 'heavyswordsman': 'سياف ثقيل', 'heavyhalberdier': 'هالبرد ثقيل',
    'heavymaceman': 'صولجان ثقيل', 'heavyaxeman': 'فأس ثقيل', 'heavylongbowman': 'قوس طويل ثقيل',
    'heavyarcher': 'رامي ثقيل', 'shortbowman': 'نشاب قصير', 'cavalryarcher': 'فارس رامي',
    'militia': 'ميليشيا', 'armedcitizen': 'مواطن مسلح', 'peasant': 'فلاح', 'defensivearcher': 'رامي دفاعي',
    'wallarcher': 'رامي سور', 'wallcrossbowman': 'قوس سور', 'wallspearman': 'رمح سور',
    'wallswordsman': 'سياف سور', 'wallmaceman': 'صولجان سور', 'wallspadesman': 'مهندس سور',
    'wallhalberdier': 'هالبرد سور', 'moatdefender': 'مدافع خندق', 'moatspearman': 'رمح خندق',
    'moatcrossbowman': 'قوس خندق', 'moatarcher': 'رامي خندق', 'gatedefender': 'مدافع بوابة',
    'gatespearman': 'رمح بوابة', 'gateswordsman': 'سياف بوابة', 'gatespadesman': 'مهندس بوابة',
    'gatecrossbowman': 'قوس بوابة', 'gatearcher': 'رامي بوابة',
    'royalknight': 'فارس ملكي', 'royalcrossbowman': 'قوس ملكي', 'royalsentinel': 'حارس ملكي',
    'royalscout': 'مستكشف ملكي', 'royalbowman': 'نشاب ملكي', 'royalspearman': 'رمح ملكي',
    'kingscrossbowman': 'قوس ملكي', 'kingsmace': 'صولجان ملكي', 'kingsmaceman': 'صولجان ملكي',
    'kingsknight': 'فارس ملكي', 'eliteknight': 'فارس نخبة', 'elitecrossbowman': 'قوس نخبة',
    'elitebowman': 'نشاب نخبة', 'elitehalberd': 'هالبرد نخبة', 'elitehalberdier': 'هالبرد نخبة',
    'elitespearman': 'رمح نخبة', 'elitespeerman': 'رمح نخبة', 'eliteswordsman': 'سياف نخبة',
    'eliteswordman': 'سياف نخبة', 'elitemace': 'صولجان نخبة', 'elitemaceman': 'صولجان نخبة',
    'elitetwohandedsword': 'سياف بيدين نخبة', 'elitetwohandedswordsman': 'سياف بيدين نخبة',
    'eliteheavycrossbowman': 'قوس ثقيل نخبة', 'elitekingscrossbowman': 'قوس ملكي نخبة',
    'elitekingsmace': 'صولجان ملكي نخبة', 'eliteheavyhalberdier': 'هالبرد ثقيل نخبة',
    'travellingknight': 'فارس مسافر', 'travellingcrossbowman': 'قوس مسافر',
    'imperialknight': 'فارس إمبراطوري', 'imperialmarksman': 'قناص إمبراطوري',
    'imperialguardsman': 'حارس إمبراطوري', 'imperialbowman': 'نشاب إمبراطوري',
    'imperialspearman': 'رمح إمبراطوري', 'imperialswordsman': 'سياف إمبراطوري',
    'khanguards': 'حراس الخان', 'sabercleaver': 'قطاع السيف', 'slingshot': 'مقذاف',
    'veteransabercleaver': 'قطاع السيف محترف', 'veteranslingshot': 'مقذاف محترف',
    'renegadelancer': 'رماح مارق', 'renegadespearthrower': 'رامي رماح مارق',
    'renegadesaiwarrior': 'محارب ساي مارق', 'renegadekunaithrower': 'رامي كوناي مارق',
    'renegadekatanawarrior': 'محارب كاتانا مارق', 'renegadebowmaster': 'سيد القوس مارق',
    'shadowmaceman': 'صولجان الظل', 'shadowcrossbowman': 'قوس الظل', 'shadowrogue': 'مارق الظل',
    'shadowfelon': 'مجرم الظل', 'shadowscoundrel': 'وغد الظل', 'shadowwretch': 'خسيس الظل',
    'demonshadow': 'ظل شيطاني', 'deathlyshadow': 'ظل مميت', 'demonhorror': 'رعب شيطاني',
    'deathlyhorror': 'رعب مميت', 'veterandemonhorror': 'رعب شيطاني محترف',
    'veterandeathlyhorror': 'رعب مميت محترف',
    'renegadestonesmasher': 'ساحق الحجر مارق', 'renegadesharktoothwarrior': 'محارب سن القرش مارق',
    'renegadesailripper': 'ممزق الشراع مارق', 'renegadeswashbuckler': 'مبارز مارق',
    'renegadenorsemanwarrior': 'محارب نورسمان مارق', 'renegadenorsemanbowman': 'نشاب نورسمان مارق',
    'barbarian': 'بربري', 'wolfhound': 'كلب ذئب', 'renegadesaberwarrior': 'محارب سيف مارق',
    'renegadedesertbowman': 'نشاب صحراوي مارق', 'renegadecultistwarrior': 'محارب طائفي مارق',
    'renegadecultistbowman': 'نشاب طائفي مارق', 'flamebearer': 'حامل الشعلة',
    'veteranflamebearer': 'حامل الشعلة محترف', 'compositebowman': 'نشاب مركب',
    'veterancompositebowman': 'نشاب مركب محترف',
    'marksman': 'قناص', 'muscleman': 'رجل العضلات', 'lionwarrior': 'محارب الأسد',
    'bearwarrior': 'محارب الدب', 'lionbowman': 'نشاب الأسد', 'bearbowman': 'نشاب الدب',
    'forsakenmaiden': 'عذراء مهجورة', 'forlornranger': 'حارسة منبوذة',
    'candycaneprotector': 'حامي عصا الحلوى', 'jollygingerbreadsniper': 'قناص الزنجبيل المرح',
    'easterchampioness': 'بطلة الفصح', 'valkyriehuntress': 'صيادة فالكيري',
    'guardianofspring': 'حامي الربيع', 'celestialmarksman': 'قناص سماوي',
    'fruitpirate': 'قرصان الفواكه', 'summerhuntress': 'صيادة الصيف', 'fruitbreaker': 'كاسر الفواكه',
    'summermarksman': 'قناص الصيف', 'steinsmasher': 'ساحق الكوب', 'caskmarksmann': 'قناص البرميل',
    'pretzelguardian': 'حامي البريتزل', 'bavarianbrewer': 'صانع جعة بافاري',
    'glacialamazonwarrior': 'محاربة أمازونية جليدية', 'glacialamazonarcher': 'رامية أمازونية جليدية',
    'glacialamazonguardian': 'حامية أمازونية جليدية', 'glacialamazonhuntress': 'صيادة أمازونية جليدية',
    'christmaswarrior': 'محارب الكريسماس', 'christmasarcher': 'رامي الكريسماس',
    'christmasguardian': 'حامي الكريسماس', 'christmashuntress': 'صيادة الكريسماس',
    'berserker': 'بيرسيركر', 'spearwoman': 'امرأة الرمح', 'gingerbreadmaiden': 'عذراء الزنجبيل',
    'masterswordsman': 'سياف أستاذ', 'masterarcher': 'رامي أستاذ', 'forestwarrior': 'محارب الغابة',
    'foresthunter': 'صياد الغابة', 'forestguardian': 'حامي الغابة', 'forestbowman': 'نشاب الغابة',
    'springhuntress': 'صيادة الربيع', 'springfootsoldier': 'جندي ربيع',
    'shamrockhuntsman': 'صياد البرسيم', 'shamrockassassin': 'سفاح البرسيم',
    'pumpkinbutcher': 'جزار اليقطين', 'ravenchomper': 'قاطع الغراب', 'skeletonwarrior': 'محارب هيكلي',
    'skeletonbowman': 'نشاب هيكلي', 'skeletalscytheman': 'حاصد هيكلي', 'skeletalhunter': 'صياد هيكلي',
    'bonerattler': 'مقلق العظام', 'firewitch': 'ساحرة النار', 'gnomadwarrior': 'محارب جوال',
    'gnomadarcher': 'رامي جوال', 'gingerbreadbrawler': 'مشاجر الزنجبيل',
    'gingerbreadsniper': 'قناص الزنجبيل', 'cowberdier': 'بقرة هالبرد', 'longbowox': 'ثور قوس طويل',
    'marauder': 'سالب', 'pyromaniac': 'مهووس بالنار', 'veteranmarauder': 'سالب محترف',
    'veteranpyromaniac': 'مهووس بالنار محترف', 'masterfrostbowman': 'نشاب الصقيع الأستاذ',
    'frostbowman': 'نشاب الصقيع', 'masterbonehuntress': 'صيادة العظام الأستاذة',
    'bonehuntress': 'صيادة العظام', 'demonslayer': 'قاتل الشياطين', 'assassin': 'سفاح',
    'renegadecavesmasher': 'ساحق الكهف مارق', 'renegadecavehunter': 'صياد الكهف مارق',
    'ladder': 'سلم', 'siegetower': 'برج حصار', 'batteringram': 'كبش حصار', 'catapult': 'منجنيق',
    'mantlet': 'متراس', 'ironmantlet': 'متراس حديدي', 'firearrow': 'سهم ناري', 'wall': 'سور',
    'gate': 'بوابة', 'moat': 'خندق',
  };

  static const Map<String, Map<String, String>> _map = {
    'ar': {
      'login': 'تسجيل الدخول', 'username': 'اسم المستخدم',
      'password': 'كلمة المرور', 'logout': 'تسجيل الخروج', 'connecting': 'جاري الاتصال...',
      'loginSuccess': 'تم الدخول بنجاح', 'loginFailed': 'فشل تسجيل الدخول',
      'mainTitle': 'لوحة التحكم', 'transferTroops': 'تحويل الجنود',
      'trainTroops': 'تدريب الجنود', 'smuggleTroops': 'تهريب الجنود', 'commanders': 'القواد',
      'transferDesc': 'نقل بين قلاعك', 'trainDesc': 'صناعة جنود جديدة', 'smuggleDesc': 'إرسال لأعضاء التحالف',
      'cmdDesc': 'إدارة حالة القواد', 'settings': 'الإعدادات', 'logoutConfirm': 'هل تريد تسجيل الخروج؟',
      'from': 'من', 'to': 'إلى', 'units': 'الجنود', 'selectUnits': 'اختر الجنود', 'selectAll': 'تحديد الكل',
      'deselectAll': 'إلغاء التحديد', 'send': 'إرسال', 'sending': 'جاري الإرسال...',
      'transferOk': 'تم التحويل بنجاح', 'transferFail': 'فشل التحويل', 'noUnitsSelected': 'لم تختر أي جنود',
      'loadingUnits': 'جاري تحميل الجنود...', 'loadUnits': 'تحميل الجنود', 'offenseOnly': 'هجومية',
      'defenseOnly': 'دفاعية', 'allUnits': 'الكل', 'total': 'الإجمالي', 'available': 'متاح',
      'amountToSend': 'الكمية', 'sameCastleError': 'لا يمكن التحويل لنفس القلعة', 'allianceMembers': 'أعضاء التحالف',
      'peaceActive': 'محمي', 'noPeaceActive': 'بدون حماية', 'peaceTime': 'وقت الحماية', 'distance': 'المسافة',
      'clicks': 'خانة', 'selectMember': 'اختر العضو', 'memberCastle': 'قلعة العضو',
      'loadingMembers': 'جاري تحميل الأعضاء...', 'noAllianceMembers': 'لا يوجد أعضاء بحماية',
      'peaceOnly': 'المحميون فقط', 'allMembers': 'كل الأعضاء', 'sendTo': 'إرسال إلى',
      'notInAlliance': 'أنت لست في تحالف، أو تعذر جلب بيانات التحالف.', 'maxMovements': 'وصلت للحد الأقصى من تحركات الجيوش.',
      'allLordsBusy': 'كل القادة مشغولين.', 'stationTime': 'وقت البقاء (ساعات)', 'selectLord': 'اختر القائد',
      'autoLord': 'اختيار تلقائي', 'commanderBusy': 'مشغول', 'commanderFree': 'متاح', 'timeRemaining': 'الوقت المتبقي',
      'recall': 'انسحاب', 'recallSuccess': 'تم إرسال أمر الانسحاب', 'recallFail': 'فشل الانسحاب',
      'noCommanders': 'لا يوجد قواد متاحين', 'selectCastle': 'اختر القلعة', 'unitType': 'نوع الجندي',
      'amount': 'الكمية', 'startTraining': 'ابدأ التدريب', 'trainingOk': 'بدأ التدريب', 'trainingFail': 'فشل التدريب',
      'cancel': 'إلغاء', 'ok': 'موافق', 'close': 'إغلاق', 'error': 'خطأ', 'retry': 'إعادة المحاولة',
      'language': 'اللغة', 'none': 'لا شيء', 'refresh': 'تحديث', 'statsTitle': 'الإحصائيات',
      'statsDesc': 'موارد، جنود، إنتاج', 'notificationsTitle': 'الإشعارات', 'notificationsDesc': 'تنبيهات الهجمات',
      'notificationsEnabled': 'تفعيل الإشعارات', 'notificationsEnabledDesc': 'استقبال إشعارات عند الهجوم',
      'soundAlert': 'صوت التنبيه', 'soundAlertDesc': 'تشغيل صوت عند وصول هجوم', 'noAlerts': 'مفيش تنبيهات',
      'noAlertsDesc': 'مفيش هجمات لحد دلوقتي — كل حاجة تمام', 'noCastles': 'مفيش قلاع', 'delete': 'حذف',
      'details': 'تفاصيل', 'deleteAll': 'حذف الكل', 'deleteAlertConfirm': 'متأكد إنك عايز تحذف الإشعار ده؟',
      'allianceAttacks': 'هجمات أعضاء التحالف', 'allianceAttacksDesc': 'تنبيه لما حد من تحالفك يتهجم عليه',
      'attackerCastle': 'قلعة المهاجم', 'targetCastle': 'القلعة المستهدفة', 'attackingUnits': 'الجنود المهاجمة',
      'defenseUnits': 'جنود الدفاع', 'defenseInfo': 'تفاصيل الدفاع',
      'defenseNotAvailable': 'افتح صفحة الإحصائيات الأول عشان تشوف تفاصيل الدفاع', 'defenseStat': 'قوة الدفاع',
      'perHour': 'ساعة', 'allianceMember': 'عضو تحالف',
    },
    'en': {
      'login': 'Login', 'username': 'Username', 'password': 'Password',
      'logout': 'Logout', 'connecting': 'Connecting...', 'loginSuccess': 'Login successful',
      'loginFailed': 'Login failed', 'mainTitle': 'Dashboard',
      'transferTroops': 'Transfer Troops', 'trainTroops': 'Train Troops', 'smuggleTroops': 'Smuggle Troops',
      'commanders': 'Commanders', 'transferDesc': 'Move between your castles', 'trainDesc': 'Create new units',
      'smuggleDesc': 'Send to peace-protected allies', 'cmdDesc': 'Manage commander status',
      'settings': 'Settings', 'logoutConfirm': 'Log out?', 'from': 'From', 'to': 'To', 'units': 'Units',
      'selectUnits': 'Select units', 'selectAll': 'Select All', 'deselectAll': 'Deselect All', 'send': 'Send',
      'sending': 'Sending...', 'transferOk': 'Transfer successful', 'transferFail': 'Transfer failed',
      'noUnitsSelected': 'No units selected', 'loadingUnits': 'Loading units...', 'loadUnits': 'Load Units',
      'offenseOnly': 'Offense', 'defenseOnly': 'Defense', 'allUnits': 'All', 'total': 'Total',
      'available': 'Available', 'amountToSend': 'Amount', 'sameCastleError': 'Cannot transfer to the same castle',
      'allianceMembers': 'Alliance Members', 'peaceActive': 'Protected', 'noPeaceActive': 'No peace',
      'peaceTime': 'Peace time', 'distance': 'Distance', 'clicks': 'clicks', 'selectMember': 'Select member',
      'memberCastle': 'Member castle', 'loadingMembers': 'Loading members...',
      'noAllianceMembers': 'No protected members', 'peaceOnly': 'Protected only', 'allMembers': 'All members',
      'sendTo': 'Send to', 'notInAlliance': 'You are not in an alliance, or could not fetch alliance data.',
      'maxMovements': 'Max kingdom army movements exceeded.', 'allLordsBusy': 'All lords are currently busy.',
      'stationTime': 'Station Time (Hours)', 'selectLord': 'Select Commander', 'autoLord': 'Auto Select',
      'commanderBusy': 'Busy', 'commanderFree': 'Available', 'timeRemaining': 'Time Remaining',
      'recall': 'Recall', 'recallSuccess': 'Recall command sent', 'recallFail': 'Recall failed',
      'noCommanders': 'No commanders found', 'selectCastle': 'Select castle', 'unitType': 'Unit type',
      'amount': 'Amount', 'startTraining': 'Start Training', 'trainingOk': 'Training started',
      'trainingFail': 'Training failed', 'cancel': 'Cancel', 'ok': 'OK', 'close': 'Close', 'error': 'Error',
      'retry': 'Retry', 'language': 'Language', 'none': 'None', 'refresh': 'Refresh', 'statsTitle': 'Statistics',
      'statsDesc': 'Resources, units, production', 'notificationsTitle': 'Notifications',
      'notificationsDesc': 'Attack alerts', 'notificationsEnabled': 'Enable notifications',
      'notificationsEnabledDesc': 'Receive alerts when attacked', 'soundAlert': 'Sound alerts',
      'soundAlertDesc': 'Play sound when attack arrives', 'noAlerts': 'No alerts', 'noAlertsDesc': 'No attacks yet',
      'noCastles': 'No castles', 'delete': 'Delete', 'details': 'Details', 'deleteAll': 'Delete All',
      'deleteAlertConfirm': 'Delete this alert?', 'allianceAttacks': 'Alliance attacks',
      'allianceAttacksDesc': 'Alert when an ally is attacked', 'attackerCastle': 'Attacker castle',
      'targetCastle': 'Target castle', 'attackingUnits': 'Attacking units', 'defenseUnits': 'Defending units',
      'defenseInfo': 'Defense info', 'defenseNotAvailable': 'Open Statistics page first to see defense info',
      'defenseStat': 'Defense stat', 'perHour': 'h', 'allianceMember': 'Alliance member',
    },
  };
}