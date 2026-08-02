(function initUiI18n(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.uiI18n = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  const DEFAULT_LOCALE = 'zh-CN';
  const SUPPORTED_LOCALES = Object.freeze(['zh-CN', 'en']);
  const originalTextNodes = new WeakMap();

  const EN = Object.freeze({
    '水滴鱼设置': 'Blobfish Settings',
    '水滴鱼': 'Blobfish',
    '别排太满。鱼也要喘气。': 'Do not pack the day too tight. Fish need room to breathe.',
    '外观与活动方式': 'LOOK & MOVEMENT',
    '换一个角色，会一起切换说话和活动的感觉。': 'Switch characters to change both its voice and movement.',
    '内置 2 个': 'Built in',
    '游动速度': 'Movement speed',
    '角色大小': 'Character size',
    '水平（沿底部左右游动）': 'Horizontal (move along the bottom)',
    '垂直（沿边缘上下游动）': 'Vertical (move along the edge)',
    '调身体、鱼鳍和五官。左边实时预览，保存后桌面上的角色才会跟着变。': 'Adjust the body, fins, and features. The preview updates now; the desktop pet updates after saving.',
    '这个形象暂时不支持捏。换回水滴鱼就可以了。': 'This character cannot be reshaped yet. Choose Blobfish to use this feature.',
    '按你的时间生活': 'FOLLOW YOUR TIME',
    '作息提醒': 'Schedule reminders',
    '到点了，它会小声提醒你。': 'It gives you a quiet reminder when the time comes.',
    '至': 'to',
    '每个自然日最多问候一次；安静时段内不会打招呼，也不会记作今天已经说过。': 'At most one greeting per day. Quiet hours neither greet nor mark the greeting as used.',
    '每周工作日': 'Weekly workdays',
    '一': 'Mon',
    '二': 'Tue',
    '三': 'Wed',
    '四': 'Thu',
    '五': 'Fri',
    '六': 'Sat',
    '日': 'Sun',
    '快速计时、重复闹钟和响铃方式会在独立小窗口里立即生效。': 'Quick timers, repeating alarms, and sounds take effect immediately in a separate window.',
    '控制它什么时候开口': 'CHOOSE WHEN IT SPEAKS',
    '选择语言，调整主动闲聊的频率，也可以单独关闭某一类提示。': 'Choose a language, adjust chatter frequency, or silence individual alert categories.',
    '让角色看见任务状态': 'LET THE PET SEE TASK STATUS',
    '每张卡片都会直接说明当前状态、下一步和可执行操作。': 'Each card shows its current state, next step, and available action.',
    '当前是 Pro…。需要时可以检查 GitHub 的正式版本。': 'This is Pro…. Check GitHub releases whenever you need.',
    '只下载与你的 Mac 芯片匹配、并通过 SHA-256 校验的完整安装包。当前文件夹不可写时，会自动改用你个人的“应用程序”文件夹，不要求管理员权限。PR、分支和 Draft 不会被一键更新发现。': 'Downloads only the complete package matching this Mac and verifies its SHA-256 digest. If the current folder is read-only, it uses your personal Applications folder without administrator access. Pull requests, branches, and draft releases are not offered as updates.',
    '本地接收器正在启动…': 'Starting the local receiver…',
    '正在检测插件…': 'Checking the plugin…',
    '你现在要做': 'What to do now',
    '检测完成后，这里会告诉你怎么做。': 'The next step will appear here after the check.',
    '查看连接过程与其他操作': 'Connection details and other actions',
    '尚无': 'None yet',
    '痛痛痛!!': 'Ow!!',
    '设置分类': 'Settings sections',
    '角色与动作': 'Character & motion',
    '形象、大小、移动': 'Character, size, movement',
    '问候与作息': 'Greetings & schedule',
    '首次见面、吃饭、下班': 'First hello, lunch, clocking off',
    '台词': 'Speech',
    '语言、闲聊、提示类型': 'Language, chatter, alerts',
    '连接与隐私': 'Connections & privacy',
    '任务状态': 'Task status',
    'Codex、Claude、日历': 'Codex, Claude, calendar',
    '右键角色，或点击菜单栏里的 🐟，可以随时回到这里。': 'Right-click the pet, or click 🐟 in the menu bar, to return here.',
    '形象与活动': 'Character & activity',
    '先选角色，再决定它怎么在桌面上活动。': 'Choose a character, then decide how it moves around your desktop.',
    '角色': 'CHARACTER',
    '选择角色': 'Choose a character',
    '切换后会自动选择最适合这个角色的语言包。': 'Switching characters also selects its matching speech pack.',
    '形象包': 'Character pack',
    '动作': 'Motion',
    '任务运行时会游动；全部结束后可以停下。': 'The pet moves while tasks run and can stop when they are all done.',
    '速度': 'Speed',
    '大小': 'Size',
    '活动方向': 'Movement direction',
    '左右移动': 'Horizontal',
    '上下移动': 'Vertical',
    '没有任务时也继续游动': 'Keep moving without tasks',
    '关闭后，所有任务结束时角色会停下来。': 'When off, the pet stops after all tasks finish.',
    '任务进行时游动': 'Move while tasks are running',
    '关闭后仍显示任务状态，只是不再在桌面上移动。': 'Task status stays visible, but the pet no longer moves around the desktop.',
    '登录后自动打开': 'Open at login',
    '在后台启动，仍然不会占用程序坞。': 'Starts in the background without taking up Dock space.',
    '性能与内存': 'Performance & memory',
    '默认不采样；打开功能后才会读取本机 CPU 和内存占用。': 'No sampling by default. CPU and memory are read only while a related feature is enabled.',
    '显示性能面板': 'Show performance panel',
    '在桌面角色旁显示系统 CPU、内存和本程序占用。': 'Shows system CPU, memory, and this app\'s memory beside the desktop pet.',
    '内存过高时自动退出': 'Quit when memory stays high',
    '连续超限 3 分钟才退出；设置、闹钟和更新期间会等待。': 'Quits only after 3 minutes above the limit, and waits during settings, alarms, or updates.',
    '内存上限': 'Memory limit',
    '自己动手': 'MAKE IT YOURS',
    '捏鱼': 'Shape fish',
    '身体、鱼鳍、五官': 'Body, fins, features',
    '恢复原样': 'Reset appearance',
    '身体': 'Body',
    '草团': 'Grass body',
    '鱼鳍': 'Fins',
    '小手': 'Hands',
    '眼睛': 'Eyes',
    '嘴巴': 'Mouth',
    '鼻子': 'Nose',
    '胖瘦': 'Width',
    '高矮': 'Height',
    '大小': 'Size',
    '宽度': 'Width',
    '高度': 'Height',
    '左右': 'Horizontal position',
    '上下': 'Vertical position',
    '间距': 'Spacing',
    '身体形状': 'Body shape',
    '草团形状': 'Grass shape',
    '鱼鳍形状': 'Fin shape',
    '手形': 'Hand shape',
    '圆润': 'Rounded',
    '窝窝头': 'Wotou',
    '水滴': 'Droplet',
    '扁圆': 'Wide oval',
    '圆团': 'Round',
    '收腰': 'Tapered',
    '椭圆': 'Oval',
    '双凸': 'Double curve',
    '单弧': 'Single arc',
    '小鳍': 'Small fins',
    '圆鳍': 'Round fins',
    '长鳍': 'Long fins',
    '尖鳍': 'Pointed fins',
    '垂手': 'Lowered hands',
    '短手': 'Short hands',
    '圆手': 'Round hands',
    '举手': 'Raised hands',
    '表情与饰品': 'Expressions & accessories',
    '表情': 'Expression',
    '原本的': 'Original',
    '头顶': 'Head',
    '眼镜': 'Eyewear',
    '手边': 'Hand',
    '闹钟位置': 'Alarm position',
    '不戴': 'None',
    '不拿': 'None',
    '设好闹钟后自动出现；这里只调整它在角色手边的位置。': 'Appears automatically when an alarm is set; adjust only its position beside the character here.',
    '每天第一次见面': 'First hello of the day',
    '在设定时段内当天第一次打开，角色会说一句早安。': 'The pet greets you the first time it opens during the chosen window.',
    '工作日早晨': 'Workday morning',
    '按下方勾选的工作日判断': 'Uses the workdays selected below',
    '休息日白天': 'Day off',
    '未勾选为工作日的星期；默认 07:00 后': 'Days not marked as workdays; starts after 07:00 by default',
    '从': 'From',
    '到': 'To',
    '工作日与时间': 'Workdays & times',
    '这里同时决定工作提醒和“工作日早晨”的判断。': 'These days control both schedule reminders and the workday greeting.',
    '吃饭时间': 'Lunch time',
    '下班时间': 'Clock-off time',
    '吃饭提醒': 'Lunch reminder',
    '提前 5 分钟说一句': 'Speaks 5 minutes beforehand',
    '下班提醒': 'Clock-off reminder',
    '提前 30 分钟和 5 分钟': 'Speaks 30 and 5 minutes beforehand',
    '半小时提醒': 'Half-hour reminder',
    '工作日每半小时一次': 'Every half hour on workdays',
    '闹钟与计时器': 'Alarms & timers',
    '设置一次或重复闹钟，也可以从这里开始倒计时。': 'Create one-off or repeating alarms, or start a countdown.',
    '打开': 'Open',
    '安静时段': 'Quiet hours',
    '紧急低电量和等待确认时，鱼还是会说话。': 'Critical battery and approval alerts still speak.',
    '启用安静时段': 'Enable quiet hours',
    '普通闲聊、问候和作息提醒会暂停。': 'Chatter, greetings, and schedule reminders are paused.',
    '开始': 'Start',
    '结束': 'End',
    '台词与惊喜': 'Speech & surprises',
    '台词是角色感最强的一层。提示只在需要时出现。': 'Speech gives each character its voice. Alerts appear only when needed.',
    '界面语言': 'Interface language',
    '设置页、菜单和状态文字使用的语言。': 'Language used by settings, menus, and status labels.',
    '显示语言': 'Display language',
    '简体中文': '简体中文',
    '语言包': 'Speech pack',
    '选择角色时会自动匹配；你也可以在这里单独更换。': 'Matched to the character automatically, or choose one independently.',
    '当前语言': 'Speech language',
    '偶尔主动说话': 'Occasional chatter',
    '在没有更重要提示时，随机挑一个时间闲聊。': 'Chats at a random time when nothing more important is happening.',
    '主动闲聊': 'Enable chatter',
    '关闭后仍会保留任务、系统和作息提示。': 'Task, system, and schedule alerts remain available.',
    '最短间隔（分钟）': 'Minimum interval (minutes)',
    '最长间隔（分钟）': 'Maximum interval (minutes)',
    '稀有彩蛋台词': 'Rare surprise lines',
    '低频出现，保留一点意外感。': 'Appears infrequently to keep a little surprise.',
    '提示类型': 'Alert categories',
    '关闭一类，只影响对应台词，不影响功能本身。': 'Turning one off only silences its speech; the feature still works.',
    '作息台词': 'Schedule speech',
    '吃饭、下班与半小时提醒': 'Lunch, clock-off, and half-hour reminders',
    '系统状态台词': 'System speech',
    '首次问候、解锁、电量与错误': 'Greetings, unlock, battery, and errors',
    '日历台词': 'Calendar speech',
    '即将开始和忙碌日程': 'Upcoming events and busy days',
    '任务台词': 'Task speech',
    'Codex / Claude Code 状态': 'Codex / Claude Code status',
    '闹钟与计时台词': 'Alarm & timer speech',
    '拿起、收起、开始与到点': 'Appearing, disappearing, starting, and ringing',
    '任务提示音': 'Task sounds',
    '分别设置需要你审核时、任务结束时的提示音。完成音效在安静时段不会响。': 'Choose separate sounds for approval requests and task completion. Completion stays silent during quiet hours.',
    '播放需要审核音效': 'Play approval-request sound',
    'Codex / Claude Code 等你确认时响一声，安静时段也会提醒。': 'Plays when Codex or Claude Code needs your approval, including during quiet hours.',
    '审核音效': 'Approval sound',
    '试听': 'Preview',
    '播放完成音效': 'Play completion sound',
    '关闭后任务完成只冒对话泡泡，不出声。': 'When off, completed tasks only show a bubble.',
    '完成音效': 'Completion sound',
    '把任务状态、日历和更新都放在本机处理。': 'Task status, calendar data, and updates are handled locally.',
    '软件更新': 'Software updates',
    '只安装与这台 Mac 芯片匹配、并通过 SHA-256 校验的正式安装包。': 'Only installs a release matching this Mac after SHA-256 verification.',
    '检查 GitHub 更新': 'Check GitHub for updates',
    '下载并更新': 'Download and update',
    '任务连接': 'Task connections',
    '每张卡只显示当前状态和下一步。连接后要用真实任务验证一次。': 'Each card shows the current state and next action. Verify with one real task after connecting.',
    '重新检测': 'Check again',
    '检测中': 'Checking',
    '正在检测…': 'Checking…',
    '找到 Codex': 'Find Codex',
    '状态插件': 'Status plugin',
    '授权 Hook': 'Authorize Hook',
    '安装后需要在 Codex 中确认': 'Confirm in Codex after installation',
    '真实任务事件': 'Real task event',
    '尚未验证': 'Not verified',
    '修复 / 更新': 'Repair / update',
    '断开连接': 'Disconnect',
    '找到 Claude Code': 'Find Claude Code',
    '新会话加载插件': 'Load plugin in new session',
    '安装后需要重新打开会话': 'Reopen the session after installation',
    '接收开关': 'Reception switches',
    '暂停接收不会卸载插件，之后可以直接恢复。': 'Pausing reception does not uninstall the plugin.',
    '接收 Codex 状态': 'Receive Codex status',
    '开始、完成、失败、等待确认': 'Started, completed, failed, needs approval',
    '接收 Claude Code 状态': 'Receive Claude Code status',
    '日历与隐私': 'Calendar & privacy',
    '状态在本机处理；任务对话内容不会发送给角色。': 'Status stays on this Mac; task conversation content is not sent to the pet.',
    'macOS 日历提醒': 'macOS Calendar reminders',
    '日历：未启用': 'Calendar: disabled',
    '显示任务短标题': 'Show short task titles',
    '仅在本机截取任务开头生成': 'Generated locally from the start of a task',
    '显示日历标题': 'Show calendar titles',
    '关闭后只提示“有日程”': 'When off, only says that an event exists',
    '恢复默认': 'Restore defaults',
    '保存更改': 'Save changes',
    'TIME WITH YOUR PET': 'TIME WITH YOUR PET',
    '时间会往前走。水滴鱼替你看着。': 'Time keeps moving. Your pet will keep watch.',
    '时间到了': 'Time is up',
    '该抬头了': 'Time to look up',
    '稍后 5 分钟': 'Snooze 5 minutes',
    '知道了': 'Dismiss',
    '计时器': 'Timer',
    '正在计时': 'Running',
    '已暂停': 'Paused',
    '还没有开始': 'Not started',
    '计时中': 'Timing',
    '暂停': 'Pause',
    '继续': 'Resume',
    '闹钟到了': 'Alarm ringing',
    '计时结束': 'Timer finished',
    '+5 分钟': '+5 minutes',
    '取消': 'Cancel',
    '快速计时': 'Quick timer',
    '5 分钟': '5 minutes',
    '15 分钟': '15 minutes',
    '专注': 'Focus',
    '45 分钟': '45 minutes',
    '自定义分钟': 'Custom minutes',
    '名称（可选）': 'Name (optional)',
    '例如：泡茶、专注': 'For example: tea, focus',
    '例如：开会、吃药': 'For example: meeting, medicine',
    '开始计时': 'Start timer',
    '设置闹钟': 'Set alarm',
    '取消编辑': 'Cancel editing',
    '时间': 'Time',
    '重复': 'Repeat',
    '仅一次': 'Once',
    '每天': 'Daily',
    '工作日': 'Workdays',
    '自选星期': 'Selected weekdays',
    '日期': 'Date',
    '星期': 'Weekdays',
    '接下来的闹钟': 'Upcoming alarms',
    '0 个': '0 alarms',
    '还没有闹钟。设一个以后，水滴鱼会把闹钟拿在手边。': 'No alarms yet. Once you set one, the pet will keep it close.',
    '响铃方式': 'Alert sounds',
    '闹钟声音': 'Alarm sound',
    '闹钟到点时播放': 'Plays when an alarm rings',
    '计时结束声音': 'Timer completion sound',
    '倒计时归零时播放': 'Plays when a countdown reaches zero',
    '安静时段仍然响铃': 'Ring during quiet hours',
    '这是你主动设置的提醒，默认不会静音': 'User-created alerts are not muted by default',
    '水滴鱼运行时会准点提醒；如果完全退出，只能在下次打开或电脑唤醒后补提醒。': 'Alerts ring on time while the pet is running. If it is fully closed, missed alerts appear the next time it opens or the Mac wakes.',
    '和水滴鱼聊天': 'Chat with your pet',
    '关闭': 'Close',
    '再等 5 分钟': 'Snooze 5 minutes',
  });

  function normalizeLocale(locale) {
    return locale === 'en' ? 'en' : DEFAULT_LOCALE;
  }

  function format(template, values = {}) {
    return String(template).replace(/\{([A-Za-z][A-Za-z0-9]*)\}/g, (match, key) => (
      Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
    ));
  }

  function t(locale, key, values) {
    const normalized = normalizeLocale(locale);
    const template = normalized === 'en' ? (EN[key] || key) : key;
    return format(template, values);
  }

  function translateNodeText(node, locale) {
    const value = node.nodeValue;
    const trimmed = value.trim();
    if (!trimmed) return;
    if (!originalTextNodes.has(node)) originalTextNodes.set(node, trimmed);
    const original = originalTextNodes.get(node);
    const translated = t(locale, original);
    node.nodeValue = value.replace(trimmed, translated);
  }

  function applyDocument(document, locale) {
    const normalized = normalizeLocale(locale);
    document.documentElement.lang = normalized === 'en' ? 'en' : 'zh-Hans';
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      if (!['SCRIPT', 'STYLE'].includes(node.parentElement?.tagName)) translateNodeText(node, normalized);
    }
    for (const element of document.querySelectorAll('[placeholder], [aria-label], [title]')) {
      for (const attribute of ['placeholder', 'aria-label', 'title']) {
        if (!element.hasAttribute(attribute)) continue;
        const originalKey = `uiI18nOriginal${attribute.replace(/(^|-)([a-z])/g, (_, dash, letter) => letter.toUpperCase())}`;
        if (!element.dataset[originalKey]) element.dataset[originalKey] = element.getAttribute(attribute);
        element.setAttribute(attribute, t(normalized, element.dataset[originalKey]));
      }
    }
    return normalized;
  }

  function englishCharacterCopy(characterId) {
    const grass = characterId === 'grass-buddy';
    if (grass) {
      return {
        windowTitle: 'Grass Buddy Settings',
        pageTitle: 'Grass Buddy',
        subtitle: 'No need to keep it together. Growing a little still counts.',
        scheduleTitle: 'A slower schedule',
        scheduleHint: 'It will remember lunch and clocking off. Slowly, but reliably.',
        greetingTitle: 'First sprout of the day',
        greetingHint: 'During the chosen window, Grass Buddy says hello the first time it appears.',
        quietTitle: 'Quiet patch',
        quietHint: 'Approval requests and critical battery alerts still get through.',
        personalityTitle: 'Character & activity',
        personalityHint: 'Choose the character first, then decide how it moves around your desktop.',
        motionTitle: 'Wandering',
        motionHint: 'It shuffles while tasks run and can settle down when they finish.',
        speedLabel: 'Shuffle speed',
        roamWithoutTasksLabel: 'Keep wandering without tasks',
        entryHint: 'Right-click the character, or click 🐟 in the menu bar, to return here.',
        savedStatus: 'Saved. Grass Buddy will think about it.',
        resetStatus: 'Back to how it first grew.',
        diyNavTitle: 'Shape grass',
        diyNavHint: 'Body, leaves, features',
        diyPanelName: 'Shape grass',
        diyKicker: 'MAKE IT YOURS',
        diyTitle: 'Shape grass',
        diyHint: 'Adjust the body, leaves, and features. The preview updates now; the desktop pet updates after saving.',
        diyUnsupported: 'This character cannot be reshaped yet.',
        diyPreviewLabel: 'Grass Buddy preview',
        diyAccessoryTitle: 'Expressions & accessories',
      };
    }
    return {
      windowTitle: 'Blobfish Settings',
      pageTitle: 'Blobfish',
      subtitle: 'Do not pack the day too tight. Fish need room to breathe.',
      scheduleTitle: 'Schedule reminders',
      scheduleHint: 'It will remember lunch and clocking off, because apparently someone has to.',
      greetingTitle: 'First hello of the day',
      greetingHint: 'During the chosen window, Blobfish says hello the first time it appears.',
      quietTitle: 'Quiet hours',
      quietHint: 'Approval requests and critical battery alerts still get through.',
      personalityTitle: 'Character & activity',
      personalityHint: 'Choose the character first, then decide how it moves around your desktop.',
      motionTitle: 'Motion',
      motionHint: 'It swims while tasks run and can stop when they all finish.',
      speedLabel: 'Swim speed',
      roamWithoutTasksLabel: 'Keep swimming without tasks',
      entryHint: 'Right-click the character, or click 🐟 in the menu bar, to return here.',
      savedStatus: 'Saved. The fish has accepted this.',
      resetStatus: 'Everything is back to default.',
      diyNavTitle: 'Shape fish',
      diyNavHint: 'Body, fins, features',
      diyPanelName: 'Shape fish',
      diyKicker: 'MAKE IT YOURS',
      diyTitle: 'Shape fish',
      diyHint: 'Adjust the body, fins, and features. The preview updates now; the desktop pet updates after saving.',
      diyUnsupported: 'This character cannot be reshaped yet. Choose Blobfish to use this feature.',
      diyPreviewLabel: 'Blobfish preview',
      diyAccessoryTitle: 'Expressions & accessories',
    };
  }

  function localizeCharacterCopy(characterId, copy, locale) {
    return normalizeLocale(locale) === 'en' ? { ...copy, ...englishCharacterCopy(characterId) } : copy;
  }

  function titleCaseId(id) {
    return String(id || '')
      .replace(/^face-/, '')
      .split('-')
      .filter(Boolean)
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }

  function localizeCharacterName(characterId, fallback, locale) {
    if (normalizeLocale(locale) !== 'en') return fallback;
    return {
      blobfish: 'Blobfish',
      'blobfish-wotou': 'Blobfish (Wotou)',
      'grass-buddy': 'Grass Buddy',
    }[characterId] || titleCaseId(characterId) || fallback;
  }

  function localizeAccessoryName(accessoryId, fallback, locale) {
    if (normalizeLocale(locale) !== 'en') return fallback;
    return titleCaseId(accessoryId) || fallback;
  }

  function localizeSoundName(soundId, fallback, locale) {
    if (normalizeLocale(locale) !== 'en') return fallback;
    const descriptions = {
      Glass: 'bright chime',
      Ping: 'clear ping',
      Hero: 'heroic',
      Submarine: 'low tone',
      Tink: 'light chime',
      Pop: 'bubble pop',
      Purr: 'soft purr',
      Bottle: 'bottle tap',
      Funk: 'funk',
    };
    return descriptions[soundId] ? `${soundId} (${descriptions[soundId]})` : (soundId || fallback);
  }

  return Object.freeze({
    DEFAULT_LOCALE,
    SUPPORTED_LOCALES,
    normalizeLocale,
    t,
    applyDocument,
    localizeCharacterCopy,
    localizeCharacterName,
    localizeAccessoryName,
    localizeSoundName,
  });
}));
