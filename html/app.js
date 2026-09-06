const app = document.getElementById('app');
const view = document.getElementById('view');
const softLeft = document.getElementById('soft-left');
const softRight = document.getElementById('soft-right');
const statusRight = document.getElementById('status-right');

let phoneData = {};
let screen = 'home';
let selected = 0;
let stack = [];
let contacts = [];
let threads = [];
let messages = [];
let messageScrollOffset = 0;
let conversationPinnedToBottom = true;
let activeNumber = '';
let activeCall = null;
let inputMode = null;
let inputValue = '';
let inputTitle = '';
let inputSubmitting = false;
let lastTypingState = null;
let draftName = '';
let draftNumber = '';
let snakeBest = 0;
let snakeLoop = null;
let snakeGame = null;

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'blixt-mokia';

const ringtone = new Audio("./assets/ringtone.mp3");
ringtone.loop = true;
ringtone.volume = 0.55;

const textTone = new Audio("assets/nokiatext.mp3");
textTone.loop = false;
textTone.volume = 0.85;
textTone.preload = "auto";

function playTextTone() {
    try {
        const tone = new Audio("assets/nokiatext.mp3");
        tone.volume = 0.85;
        tone.preload = "auto";
        tone.currentTime = 0;

        const playPromise = tone.play();

        if (playPromise && typeof playPromise.catch === "function") {
            playPromise.catch(() => {
                try {
                    textTone.pause();
                    textTone.currentTime = 0;
                    textTone.play().catch(() => {});
                } catch (e) {}
            });
        }
    } catch (e) {}
}

function startRingtone() {
    try {
        ringtone.currentTime = 0;
        const playPromise = ringtone.play();
        if (playPromise && typeof playPromise.catch === "function") {
            playPromise.catch(() => {});
        }
    } catch (e) {}
}

function stopRingtone() {
    try {
        ringtone.pause();
        ringtone.currentTime = 0;
    } catch (e) {}
}

function post(name, data = {}) {
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then(r => r.json()).catch(() => ({}));
}

let uiAudio = null;

function getUiAudio() {
    try {
        if (!uiAudio) {
            uiAudio = new (window.AudioContext || window.webkitAudioContext)();
        }

        if (uiAudio.state === 'suspended') {
            uiAudio.resume().catch(() => {});
        }

        return uiAudio;
    } catch (e) {
        return null;
    }
}

function tone(frequency = 880, duration = 0.035, volume = 0.018, type = 'square', delay = 0) {
    try {
        const audio = getUiAudio();
        if (!audio) return;

        const startAt = audio.currentTime + delay;
        const osc = audio.createOscillator();
        const gain = audio.createGain();

        osc.type = type;
        osc.frequency.setValueAtTime(frequency, startAt);
        gain.gain.setValueAtTime(0.0001, startAt);
        gain.gain.exponentialRampToValueAtTime(Math.max(volume, 0.0001), startAt + 0.006);
        gain.gain.exponentialRampToValueAtTime(0.0001, startAt + duration);

        osc.connect(gain);
        gain.connect(audio.destination);
        osc.start(startAt);
        osc.stop(startAt + duration + 0.012);
    } catch (e) {}
}

function beep() {
    // Discreet keypad blip for every phone button press.
    tone(760, 0.028, 0.012, 'square');
}

function snakeMoveSound() {
    tone(310, 0.018, 0.006, 'square');
}

function snakeEatSound() {
    tone(720, 0.035, 0.018, 'square');
    tone(980, 0.04, 0.014, 'square', 0.035);
}

function snakeGameOverSound() {
    tone(260, 0.08, 0.018, 'sawtooth');
    tone(170, 0.10, 0.014, 'sawtooth', 0.075);
}

function snakePauseSound() {
    tone(520, 0.026, 0.01, 'square');
}

function setSoft(action = 'Select', back = 'Back', mid = '') {
    // Physical layout:
    // left label = C/back/exit/cancel side
    // right label = select/ok/reply/play side
    // middle label intentionally unused
    softLeft.textContent = back || '';
    document.getElementById('soft-mid').textContent = '';
    softRight.textContent = action || '';
}

function setPhoneTypingState(typing, force = false) {
    typing = Boolean(typing);

    if (!force && lastTypingState === typing) {
        return;
    }

    lastTypingState = typing;
    post('setTypingState', { typing });
}

function updateClock() {
    const d = new Date();
    statusRight.textContent = `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
}
setInterval(updateClock, 1000);
updateClock();

function escapeHtml(str) {
    return String(str ?? '').replace(/[&<>"']/g, s => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    }[s]));
}

function formatPhoneNumber(number) {
    const digits = String(number ?? '').replace(/\D/g, '');

    if (digits.length === 10 && !digits.startsWith('04')) {
        return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
    }

    return String(number ?? '');
}

function push(next) {
    stack.push(screen);
    selected = 0;
    screen = next;
    render();
}

function back() {
    if (inputMode) {
        inputMode = null;
        inputValue = '';
        inputTitle = '';
        inputSubmitting = false;
        render();
        return;
    }

    if (screen === 'snakeGame') {
        stopSnakeLoop();
        snakeGame = null;
    }

    if (screen === 'home') {
        closePhone();
        return;
    }

    screen = stack.pop() || 'home';
    selected = 0;
    render();
}

function menu(title, items) {
    const safeItems = Array.isArray(items) ? items : [];
    selected = Math.min(Math.max(selected, 0), Math.max(safeItems.length - 1, 0));

    const hasTitle = Boolean(title);
    const visibleCount = 6;
    const maxStart = Math.max(0, safeItems.length - visibleCount);
    const start = Math.min(Math.max(0, selected - visibleCount + 1), maxStart);
    const visible = safeItems.slice(start, start + visibleCount);

    let html = hasTitle ? `<div class="title">${escapeHtml(title)}</div>` : '';
    html += '<div class="menu-list">';

    visible.forEach((item, i) => {
        const realIndex = start + i;
        const itemNumber = realIndex + 1;
        html += `<div class="menu-item ${realIndex === selected ? 'selected' : ''}"><span class="menu-index">${itemNumber}.</span>${escapeHtml(item.label)}</div>`;
    });

    if (safeItems.length > visibleCount) {
        const thumbHeight = Math.max(18, Math.round((visibleCount / safeItems.length) * 100));
        const thumbTop = maxStart === 0 ? 0 : Math.round((start / maxStart) * (100 - thumbHeight));
        html += `<div class="scroll-track"><div class="scroll-thumb" style="height:${thumbHeight}%;top:${thumbTop}%"></div></div>`;
    }

    html += '</div>';
    view.innerHTML = html;
    setSoft('Select', screen === 'home' ? 'Exit' : 'Back');
}

const mainMenu = [
    { label: 'Contacts', action: async () => { await loadContacts(); push('contacts'); } },
    { label: 'Messages', action: async () => { await ensureContactsLoaded(); await loadThreads(); push('threads'); } },
    { label: 'Dial Number', action: () => startInput('dial', 'Dial Number') },
    { label: 'My Number', action: () => push('myNumber') },
    { label: 'Settings', action: () => push('settings') },
    { label: 'Snake', action: async () => { await openSnakeMenu(); } }
];

async function loadContacts() {
    contacts = await post('getContacts');
}

async function loadThreads() {
    threads = await post('getThreads');
}

async function loadMessages(number, keepScroll = false) {
    activeNumber = number;
    messages = await post('getMessages', { number });

    if (!keepScroll) {
        messageScrollOffset = 0;
        conversationPinnedToBottom = true;
    }
}

function getSavedContactName(number) {
    const digits = String(number ?? '').replace(/\D/g, '');
    if (!digits) return '';

    const contact = contacts.find(c => String(c.phone_number ?? '').replace(/\D/g, '') === digits);
    return contact?.name || '';
}

function getContactDisplayName(number) {
    return getSavedContactName(number) || formatPhoneNumber(number);
}

async function ensureContactsLoaded() {
    if (!Array.isArray(contacts) || contacts.length === 0) {
        await loadContacts();
    }
}

async function loadSnakeTopScore() {
    const result = await post('getSnakeTopScore');
    snakeBest = Number(result?.topScore || 0);
    return snakeBest;
}

async function saveSnakeScore(score) {
    const result = await post('saveSnakeScore', { score });
    if (result && typeof result.topScore !== 'undefined') {
        snakeBest = Number(result.topScore || 0);
    }
    return result || { success: false, topScore: snakeBest, newHigh: false };
}

function stopSnakeLoop() {
    if (snakeLoop) {
        clearInterval(snakeLoop);
        snakeLoop = null;
    }
}

function randomSnakeFood(cols, rows, snake) {
    const occupied = new Set(snake.map(part => `${part.x}:${part.y}`));
    const freeCells = [];

    for (let y = 0; y < rows; y += 1) {
        for (let x = 0; x < cols; x += 1) {
            if (!occupied.has(`${x}:${y}`)) {
                freeCells.push({ x, y });
            }
        }
    }

    if (freeCells.length === 0) return null;

    return freeCells[Math.floor(Math.random() * freeCells.length)];
}

function queueSnakeDirection(direction) {
    if (!snakeGame || snakeGame.gameOver || snakeGame.turnLocked) return;

    const opposites = {
        up: 'down',
        down: 'up',
        left: 'right',
        right: 'left'
    };

    if (direction === snakeGame.dir || opposites[snakeGame.dir] === direction) return;

    snakeGame.nextDir = direction;
    snakeGame.turnLocked = true;
    snakeMoveSound();
}

async function finishSnakeGame() {
    if (!snakeGame || snakeGame.saved) return;

    snakeGame.saved = true;
    const result = await saveSnakeScore(snakeGame.score);
    snakeGame.topScore = Number(result?.topScore || snakeBest || 0);
    snakeGame.newHigh = Boolean(result?.newHigh);
    render();
}

function snakeTick() {
    if (!snakeGame || screen !== 'snakeGame' || snakeGame.paused || snakeGame.gameOver) return;

    snakeGame.dir = snakeGame.nextDir || snakeGame.dir;

    const head = { ...snakeGame.snake[0] };
    if (snakeGame.dir === 'up') head.y -= 1;
    if (snakeGame.dir === 'down') head.y += 1;
    if (snakeGame.dir === 'left') head.x -= 1;
    if (snakeGame.dir === 'right') head.x += 1;

    head.x = (head.x + snakeGame.cols) % snakeGame.cols;
    head.y = (head.y + snakeGame.rows) % snakeGame.rows;

    const willEat = snakeGame.food && head.x === snakeGame.food.x && head.y === snakeGame.food.y;
    const collisionBody = willEat ? snakeGame.snake : snakeGame.snake.slice(0, -1);
    const hitSelf = collisionBody.some(part => part.x === head.x && part.y === head.y);

    if (hitSelf) {
        snakeGame.gameOver = true;
        snakeGame.paused = false;
        stopSnakeLoop();
        snakeGameOverSound();
        finishSnakeGame();
        render();
        return;
    }

    snakeGame.snake.unshift(head);

    if (willEat) {
        snakeGame.score += 10;
        snakeEatSound();
        snakeGame.food = randomSnakeFood(snakeGame.cols, snakeGame.rows, snakeGame.snake);
    } else {
        snakeGame.snake.pop();
    }

    snakeGame.turnLocked = false;
    render();
}

function startSnakeLoop() {
    stopSnakeLoop();
    snakeLoop = setInterval(snakeTick, 185);
}

function newSnakeGame() {
    stopSnakeLoop();

    snakeGame = {
        cols: 10,
        rows: 8,
        snake: [
            { x: 4, y: 4 },
            { x: 3, y: 4 },
            { x: 2, y: 4 }
        ],
        dir: 'right',
        nextDir: 'right',
        food: null,
        score: 0,
        paused: false,
        gameOver: false,
        saved: false,
        newHigh: false,
        turnLocked: false,
        topScore: Number(snakeBest || 0)
    };

    snakeGame.food = randomSnakeFood(snakeGame.cols, snakeGame.rows, snakeGame.snake);
    snakePauseSound();
    startSnakeLoop();
    render();
}

async function openSnakeMenu() {
    await loadSnakeTopScore();
    push('snakeMenu');
}

async function openSnakeTopScore() {
    await loadSnakeTopScore();
    push('snakeTopScore');
}

function startInput(mode, title = '') {
    inputMode = mode;
    inputValue = '';
    inputTitle = title;
    inputSubmitting = false;
    render();
}

function inputMeta() {
    const title = inputTitle || 'Input';

    const helperByMode = {
        dial: 'Enter number',
        smsNumber: 'Enter number',
        smsMessage: 'Enter message',
        replyMessage: 'Enter message',
        contactName: 'Enter name',
        contactNumber: 'Enter number'
    };

    return {
        title,
        helper: helperByMode[inputMode] || ''
    };
}

function renderHome() {
    menu('', mainMenu);
}

function renderContacts() {
    const items = [
        { label: '+ Add Contact', action: () => startInput('contactName', 'Add Contact') },
        ...contacts.map(c => ({
            label: `${c.name} ${formatPhoneNumber(c.phone_number)}`,
            action: () => {
                activeNumber = c.phone_number;
                push('contactActions');
            }
        }))
    ];
    menu('Contacts', items);
}

function renderContactActions() {
    menu(formatPhoneNumber(activeNumber), [
        { label: 'Call', action: () => startCall(activeNumber) },
        { label: 'Text', action: async () => { await ensureContactsLoaded(); await loadMessages(activeNumber); push('conversation'); } },
        { label: 'Delete', action: async () => {
            const c = contacts.find(x => x.phone_number === activeNumber);
            if (c) await post('deleteContact', { id: c.id });
            await loadContacts();
            screen = 'contacts';
            render();
        }}
    ]);
}

function renderThreads() {
    const items = [
        { label: 'New Message', action: () => startInput('smsNumber', 'New Message') },
        ...threads.map(t => ({
            label: `${formatPhoneNumber(t.other_number)}: ${t.last_message || ''}`,
            action: async () => { await ensureContactsLoaded(); await loadMessages(t.other_number); push('conversation'); }
        }))
    ];
    menu('Messages', items);
}

function getConversationListElement() {
    return document.querySelector('.message-list');
}

function scrollConversation(direction) {
    const list = getConversationListElement();
    if (!list) return false;

    const amount = Math.max(16, Math.round(list.clientHeight * 0.45));

    if (direction === 'up') {
        list.scrollTop = Math.max(0, list.scrollTop - amount);
    } else {
        list.scrollTop = Math.min(list.scrollHeight, list.scrollTop + amount);
    }

    conversationPinnedToBottom = list.scrollTop + list.clientHeight >= list.scrollHeight - 2;
    return true;
}

function pinConversationToBottom() {
    const list = getConversationListElement();
    if (!list) return;

    list.scrollTop = list.scrollHeight;
    conversationPinnedToBottom = true;
}

function renderConversation() {
    const title = getContactDisplayName(activeNumber);

    let html = `<div class="title">${escapeHtml(title)}</div><div class="message-list" id="message-list">`;

    messages.forEach(m => {
        const out = m.sender_number === phoneData.number;
        const senderLabel = out ? 'Me' : getContactDisplayName(m.sender_number);
        html += `
            <div class="message-entry ${out ? 'out' : 'in'}">
                <div class="message-sender">${escapeHtml(senderLabel)}</div>
                <div class="bubble ${out ? 'out' : 'in'}">${escapeHtml(m.content)}</div>
            </div>
        `;
    });

    html += `</div>`;
    view.innerHTML = html;
    setSoft('Reply', 'Back');

    requestAnimationFrame(() => {
        const list = getConversationListElement();
        if (!list) return;

        if (conversationPinnedToBottom) {
            list.scrollTop = list.scrollHeight;
        }
    });
}

function renderMyNumber() {
    view.innerHTML = `
        <div class="title">My Number</div>
        <div class="big-icon">☎</div>
        <div class="center">${escapeHtml(formatPhoneNumber(phoneData.number) || 'No Number')}</div>
        <div class="center small">${escapeHtml(phoneData.name || '')}</div>
    `;
    setSoft('OK', 'Back', '');
}

function renderSettings() {
    const privateMode = phoneData.callerIdPrivate === true;
    menu('Settings', [
        {
            label: `Caller ID: ${privateMode ? 'Private' : 'Shown'}`,
            action: async () => {
                const result = await post('setCallerIdPrivate', { enabled: !privateMode });
                if (result?.success) {
                    phoneData.callerIdPrivate = result.callerIdPrivate === true;
                }
                render();
            }
        }
    ]);
}

function renderSnakeMenu() {
    menu('Snake', [
        { label: 'New Game', action: () => { push('snakeGame'); newSnakeGame(); } },
        { label: 'Top Score', action: async () => { await openSnakeTopScore(); } }
    ]);
}

function renderSnakeTopScore() {
    view.innerHTML = `
        <div class="title">Snake</div>
        <div class="snake-score-card">
            <div class="snake-score-label">Top Score</div>
            <div class="snake-score-value">${escapeHtml(snakeBest)}</div>
        </div>
    `;
    setSoft('Play', 'Back', '');
}

function renderSnakeGame() {
    const game = snakeGame;
    if (!game) {
        view.innerHTML = '<div class="title">Snake</div><div class="center">Starting...</div>';
        setSoft('OK', 'Back', '');
        return;
    }

    let cells = '';
    for (let y = 0; y < game.rows; y += 1) {
        for (let x = 0; x < game.cols; x += 1) {
            let classes = 'snake-cell';
            if (game.food && game.food.x === x && game.food.y === y) classes += ' food';
            if (game.snake.some((part, index) => part.x === x && part.y === y)) {
                classes += ' snake';
                if (game.snake[0].x === x && game.snake[0].y === y) classes += ' head';
            }
            cells += `<div class="${classes}"></div>`;
        }
    }

    let stateText = '';
    if (game.paused) stateText = 'Paused';
    if (game.gameOver) stateText = game.newHigh ? 'New top score!' : 'Game Over';

    const footer = game.gameOver
        ? `<div class="snake-help">Score ${escapeHtml(game.score)} | Best ${escapeHtml(game.topScore ?? snakeBest)}</div>`
        : (stateText ? `<div class="snake-help">${escapeHtml(stateText)}</div>` : '');

    view.innerHTML = `
        <div class="snake-stats">
            <span>Score ${escapeHtml(game.score)}</span>
            <span>Best ${escapeHtml(game.topScore ?? snakeBest)}</span>
        </div>
        <div class="snake-grid">${cells}</div>
        ${footer}
    `;

    if (game.gameOver) {
        setSoft('Again', 'Back', '');
    } else if (game.paused) {
        setSoft('Resume', 'Back', '');
    } else {
        setSoft('Pause', 'Back', '');
    }
}

function renderInput() {
    const meta = inputMeta();

    view.innerHTML = `
        <div class="title">${escapeHtml(meta.title)}</div>
        <div class="input">${escapeHtml(inputValue || '_')}</div>
        ${meta.helper ? `<div class="small center">${escapeHtml(meta.helper)}</div>` : ''}
    `;
    setSoft('OK', 'Cancel', inputMode && inputMode.toLowerCase().includes('message') ? 'TXT' : '123');
}

function renderCall() {
    const status = activeCall?.status || 'Calling';
    const number = activeCall?.number || '';
    const displayNumber = activeCall?.private ? 'PRIVATE NUMBER' : formatPhoneNumber(number);
    view.innerHTML = `
        <div class="title">${escapeHtml(status)}</div>
        <div class="big-icon">☎</div>
        <div class="center">${escapeHtml(displayNumber)}</div>
        <div class="center small">${escapeHtml(activeCall?.hint || '')}</div>
    `;
    setSoft(activeCall?.incoming ? 'Answer' : 'End', activeCall?.incoming ? 'Reject' : 'Back', '');
}

function render() {
    setPhoneTypingState(Boolean(inputMode));

    if (inputMode) return renderInput();

    if (activeCall && (screen === 'call' || activeCall.force)) {
        screen = 'call';
        return renderCall();
    }

    if (screen === 'home') return renderHome();
    if (screen === 'contacts') return renderContacts();
    if (screen === 'contactActions') return renderContactActions();
    if (screen === 'threads') return renderThreads();
    if (screen === 'conversation') return renderConversation();
    if (screen === 'myNumber') return renderMyNumber();
    if (screen === 'settings') return renderSettings();
    if (screen === 'snakeMenu') return renderSnakeMenu();
    if (screen === 'snakeTopScore') return renderSnakeTopScore();
    if (screen === 'snakeGame') return renderSnakeGame();
}

function currentItems() {
    if (screen === 'home') return mainMenu;
    if (screen === 'contacts') {
        return [
            { label: '+ Add Contact', action: () => startInput('contactName', 'Add Contact') },
            ...contacts.map(c => ({
                label: `${c.name} ${formatPhoneNumber(c.phone_number)}`,
                action: () => {
                    activeNumber = c.phone_number;
                    push('contactActions');
                }
            }))
        ];
    }
    if (screen === 'settings') {
        const privateMode = phoneData.callerIdPrivate === true;
        return [
            {
                label: `Caller ID: ${privateMode ? 'Private' : 'Shown'}`,
                action: async () => {
                    const result = await post('setCallerIdPrivate', { enabled: !privateMode });
                    if (result?.success) {
                        phoneData.callerIdPrivate = result.callerIdPrivate === true;
                    }
                    render();
                }
            }
        ];
    }
    if (screen === 'contactActions') {
        return [
            { label: 'Call', action: () => startCall(activeNumber) },
            { label: 'Text', action: async () => { await ensureContactsLoaded(); await loadMessages(activeNumber); push('conversation'); } },
            { label: 'Delete', action: async () => {
                const c = contacts.find(x => x.phone_number === activeNumber);
                if (c) await post('deleteContact', { id: c.id });
                await loadContacts();
                screen = 'contacts';
                render();
            }}
        ];
    }
    if (screen === 'threads') {
        return [
            { label: 'New Message', action: () => startInput('smsNumber', 'New Message') },
            ...threads.map(t => ({
                label: `${formatPhoneNumber(t.other_number)}: ${t.last_message || ''}`,
                action: async () => { await ensureContactsLoaded(); await loadMessages(t.other_number); push('conversation'); }
            }))
        ];
    }
    if (screen === 'snakeMenu') {
        return [
            { label: 'New Game', action: () => { push('snakeGame'); newSnakeGame(); } },
            { label: 'Top Score', action: async () => { await openSnakeTopScore(); } }
        ];
    }
    return [];
}

async function selectAction() {
    if (inputMode) {
        await submitInput();
        return;
    }

    if (screen === 'conversation') {
        inputMode = 'replyMessage';
        inputValue = '';
        inputTitle = 'Reply';
        render();
        return;
    }

    if (screen === 'snakeTopScore') {
        push('snakeGame');
        newSnakeGame();
        return;
    }

    if (screen === 'snakeGame') {
        if (!snakeGame) return;

        if (snakeGame.gameOver) {
            newSnakeGame();
        } else {
            snakeGame.paused = !snakeGame.paused;
            snakePauseSound();
            if (!snakeGame.paused) {
                startSnakeLoop();
            }
            render();
        }
        return;
    }

    if (screen === 'call' && activeCall) {
        if (activeCall.incoming) {
            post('answerCall', { callId: activeCall.callId });
        } else {
            post('endCall', { callId: activeCall.callId });
        }
        return;
    }

    const items = currentItems();
    const item = items[selected];
    if (item && item.action) await item.action();
}

async function submitInput() {
    if (inputSubmitting) return;

    const val = inputValue.trim();

    if (inputMode === 'dial') {
        inputMode = null;
        inputTitle = '';
        if (val) startCall(val);
        render();
        return;
    }

    if (inputMode === 'smsNumber') {
        if (!val) return;
        activeNumber = val;
        inputMode = 'smsMessage';
        inputValue = '';
        inputTitle = inputTitle || 'New Message';
        render();
        return;
    }

    if (inputMode === 'smsMessage' || inputMode === 'replyMessage') {
        if (!val) return;
        inputSubmitting = true;
        await post('sendMessage', { number: activeNumber, message: val });
        inputMode = null;
        inputValue = '';
        inputTitle = '';
        inputSubmitting = false;
        await ensureContactsLoaded();
        await loadMessages(activeNumber);
        screen = 'conversation';
        render();
        return;
    }

    if (inputMode === 'contactName') {
        if (!val) return;
        draftName = val;
        inputMode = 'contactNumber';
        inputValue = '';
        inputTitle = inputTitle || 'Add Contact';
        render();
        return;
    }

    if (inputMode === 'contactNumber') {
        if (!val) return;
        draftNumber = val;
        inputSubmitting = true;
        await post('addContact', { name: draftName, number: draftNumber });
        inputMode = null;
        inputValue = '';
        inputTitle = '';
        inputSubmitting = false;
        await loadContacts();
        screen = 'contacts';
        render();
    }
}

async function startCall(number) {
    activeCall = { number, status: 'Calling', incoming: false, force: true, hint: 'Waiting...' };
    screen = 'call';
    render();

    const result = await post('startCall', { number });
    if (!result.success) {
        activeCall = { number, status: 'Failed', incoming: false, force: true, hint: result.message || 'Unavailable' };
        render();
        setTimeout(() => { activeCall = null; screen = 'home'; render(); }, 1600);
    }
}

function closePhone() {
    stopRingtone();
    stopSnakeLoop();
    snakeGame = null;
    setPhoneTypingState(false, true);
    app.classList.add('hidden');
    post('close');
}

function handleSnakeKey(k) {
    if (screen === 'snakeTopScore') {
        if (k === 'select' || k === 'left') {
            push('snakeGame');
            newSnakeGame();
            return true;
        }

        if (k === 'right' || k === 'hang') {
            back();
            return true;
        }

        return false;
    }

    if (screen !== 'snakeGame' || !snakeGame) return false;

    if (k === 'up' || k === '8') {
        queueSnakeDirection('up');
        return true;
    }
    if (k === 'down' || k === '2') {
        queueSnakeDirection('down');
        return true;
    }
    if (k === '4') {
        queueSnakeDirection('left');
        return true;
    }
    if (k === '6') {
        queueSnakeDirection('right');
        return true;
    }

    if (k === 'select' || k === '5' || k === 'left') {
        if (snakeGame.gameOver) {
            newSnakeGame();
        } else {
            snakeGame.paused = !snakeGame.paused;
            snakePauseSound();
            if (!snakeGame.paused) {
                startSnakeLoop();
            }
            render();
        }
        return true;
    }

    if (k === 'right' || k === 'hang') {
        back();
        return true;
    }

    return false;
}

function keyPress(k) {
    beep();

    if (handleSnakeKey(k)) {
        return;
    }

    if (inputMode) {
        if (k === 'right') {
            if (inputValue.length > 0) {
                inputValue = inputValue.slice(0, -1);
                render();
            } else {
                back();
            }
            return;
        }

        if (/^[0-9]$/.test(k) || k === 'star' || k === 'hash' || k === '*' || k === '#') {
            inputValue += k === 'star' ? '*' : k === 'hash' ? '#' : k;
            render();
            return;
        }
    }

    if (!inputMode && /^[1-9]$/.test(k)) {
        const items = currentItems();
        const shortcutIndex = Number(k) - 1;
        if (items[shortcutIndex]) {
            selected = shortcutIndex;
            render();
            selectAction();
            return;
        }
    }

    if (k === 'up') {
        if (screen === 'conversation') {
            scrollConversation('up');
            return;
        }

        selected = Math.max(0, selected - 1);
        render();
        return;
    }

    if (k === 'down') {
        if (screen === 'conversation') {
            scrollConversation('down');
            return;
        }

        const count = currentItems().length;
        selected = Math.min(Math.max(count - 1, 0), selected + 1);
        render();
        return;
    }

    if (k === 'select' || k === 'left') {
        selectAction();
        return;
    }

    if (k === 'right') {
        if (screen === 'call' && activeCall?.incoming) {
            post('declineCall', { callId: activeCall.callId });
            return;
        }
        back();
        return;
    }

    if (k === 'hang') {
        if (activeCall) {
            post('endCall', { callId: activeCall.callId });
        } else {
            closePhone();
        }
        return;
    }

    if (k === 'call') {
        if (screen === 'contactActions') startCall(activeNumber);
        if (screen === 'call' && activeCall?.incoming) post('answerCall', { callId: activeCall.callId });
    }
}

document.querySelectorAll('button[data-key]').forEach(btn => {
    btn.addEventListener('click', () => keyPress(btn.dataset.key));
});

document.addEventListener('keydown', e => {
    if (app.classList.contains('hidden')) return;

    if (screen === 'snakeGame' || screen === 'snakeTopScore') {
        if (['2', '4', '5', '6', '8'].includes(e.key)) {
            keyPress(e.key);
            return;
        }
    }

    if (inputMode) {
        if (e.key.length === 1) {
            e.preventDefault();
            e.stopPropagation();
            inputValue += e.key;
            render();
            return;
        }

        if (e.key === 'Backspace') {
            e.preventDefault();
            e.stopPropagation();
            inputValue = inputValue.slice(0, -1);
            render();
            return;
        }

        if (e.key === 'Enter') {
            e.preventDefault();
            e.stopPropagation();
            keyPress('select');
            return;
        }

        if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            back();
            return;
        }
    }

    if (e.key === 'ArrowUp') keyPress('up');
    if (e.key === 'ArrowDown') keyPress('down');
    if (e.key === 'ArrowLeft') keyPress('4');
    if (e.key === 'ArrowRight') keyPress('6');
    if (e.key === 'Enter') keyPress('select');
    if (e.key === 'Escape') back();
    if (e.key === 'Backspace') back();
});

window.addEventListener('message', async event => {
    const { action, data } = event.data || {};

    if (action === 'open') {
        stopSnakeLoop();
        snakeGame = null;
        setPhoneTypingState(false, true);
        inputSubmitting = false;
        app.classList.remove('hidden');
        screen = 'home';
        selected = 0;
        stack = [];
        render();
    }

    if (action === 'close') {
        stopRingtone();
        stopSnakeLoop();
        snakeGame = null;
        setPhoneTypingState(false, true);
        inputSubmitting = false;
        app.classList.add('hidden');
    }

    if (action === 'phoneData') {
        phoneData = data || {};
        render();
    }

    if (action === 'newMessage') {
        playTextTone();

        const fromDigits = String(data?.from ?? '').replace(/\D/g, '');
        const activeDigits = String(activeNumber ?? '').replace(/\D/g, '');

        if (!app.classList.contains('hidden') && screen === 'conversation' && fromDigits === activeDigits) {
            const list = getConversationListElement();
            const wasAtBottom = !list || (list.scrollTop + list.clientHeight >= list.scrollHeight - 2);

            conversationPinnedToBottom = wasAtBottom;
            await loadMessages(activeNumber, true);
            render();
        }
    }

    if (action === 'incomingCall') {
        startRingtone();

        const isPrivate = data?.private === true;
        let savedName = '';

        if (!isPrivate && data?.number) {
            await ensureContactsLoaded();
            savedName = getSavedContactName(data.number);
        }

        activeCall = {
            callId: data.callId,
            number: isPrivate ? '' : data.number,
            private: isPrivate,
            status: 'Incoming',
            incoming: true,
            force: true,
            hint: savedName
        };
        screen = 'call';
        render();
    }

    if (action === 'outgoingCall') {
        activeCall = {
            callId: data.callId,
            number: data.number,
            status: 'Calling',
            incoming: false,
            force: true,
            hint: 'Ringing...'
        };
        screen = 'call';
        render();
    }

    if (action === 'callStarted') {
        stopRingtone();

        const isPrivate = data?.private === true;
        let hint = 'Connected';

        if (!isPrivate && data?.number) {
            await ensureContactsLoaded();
            const savedName = getSavedContactName(data.number);
            if (savedName) hint = savedName;
        }

        activeCall = {
            callId: data.callId,
            number: isPrivate ? '' : data.number,
            private: isPrivate,
            status: 'In Call',
            incoming: false,
            force: true,
            hint
        };
        screen = 'call';
        render();
    }

    if (action === 'callEnded') {
        stopRingtone();
        const reason = data?.reason || 'Ended';
        activeCall = {
            status: reason,
            number: '',
            incoming: false,
            force: true,
            hint: ''
        };
        render();
        setTimeout(() => {
            activeCall = null;
            screen = 'home';
            render();
        }, 1400);
    }
});
