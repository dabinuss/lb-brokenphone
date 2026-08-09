const display = document.getElementById('damage-display');
const overlay = document.getElementById('damage-overlay');

const cracks = {
    1: [
        'cracks/light/30664a61-4b38-4699-8354-e49c414f6f77.png',
        'cracks/light/33e64ce2-89d6-4707-bd04-3c12c7c6abad.png',
        'cracks/light/48af7dc8-8c95-42cd-9f06-29262d1c7358.png',
        'cracks/light/68b11a02-864e-4816-8e7f-c879eb1f6efe.png',
        'cracks/light/cefd428e-3d70-489a-9b72-5466cf2d9e6b.png',
        'cracks/light/f715b39b-13ad-4aed-a157-7b5402bce46d.png',
        'cracks/light/k0dc0kvq038c02q89jnvia6qw48vql1z.png'
    ],
    2: [
        'cracks/medium/957b5d53-68eb-4834-9f6d-e3c22f0c2401.png',
        'cracks/medium/chatgpt-2026-08-09-171434.png',
        'cracks/medium/fbf49129-df44-474c-9736-78047324d523.png'
    ],
    3: [
        'cracks/severe/150ee003-5f6a-4597-94b8-97d6a0469e41.png',
        'cracks/severe/25855c00-68e7-43d6-95f1-bab50a3a313f.png',
        'cracks/severe/4b6f78c3-9b59-41a8-9971-aede42f4c1ca.png',
        'cracks/severe/5f5d6a46-68fc-465f-a7cc-bf3f4d61b740.png',
        'cracks/severe/6a2fc772-2ce8-4ed9-84ac-35d3bafa663e.png'
    ]
};
const layerCounts = { 1: 3, 2: 2, 3: 1 };
const phaseSeedStep = 1000003;

function random(seed) {
    let value = (Number(seed) || 1) | 0;
    value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
    value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
    return ((value ^ (value >>> 16)) >>> 0) / 4294967296;
}

function applyLayout(config) {
    if (!config) return;
    const root = document.documentElement.style;
    for (const key of ['width', 'height', 'right', 'bottom', 'radius']) {
        if (config[key] !== undefined) root.setProperty(`--display-${key}`, String(config[key]));
    }
}

function applyMotion(state, config) {
    const root = document.documentElement.style;
    const opening = state === 'opening' || state === 'open';
    const duration = opening ? (config && config.openDuration) : (config && config.closeDuration);
    root.setProperty('--motion-y', opening ? ((config && config.openY) || '0rem') : ((config && config.closedY) || '62rem'));
    root.setProperty('--motion-duration', `${Number(duration) || 350}ms`);
    root.setProperty('--motion-easing', (config && config.easing) || 'ease-out');
}

function render(data) {
    const state = ['closed', 'opening', 'open', 'closing'].includes(data.state) ? data.state : 'closed';
    const level = Math.max(0, Math.min(3, Number(data.damageLevel) || 0));
    const seed = Number(data.damageSeed) || 1;

    applyLayout(data.display);
    applyMotion(state, data.motion);
    display.className = state;
    display.dataset.damage = String(level);

    if (!level || !cracks[level]) {
        overlay.style.backgroundImage = 'none';
        return;
    }

    const backgrounds = [];
    const positions = [];
    const sizes = [];
    for (let phase = 1; phase <= level; phase += 1) {
        const phaseSeed = seed + (phase - 1) * phaseSeedStep;
        const values = [random(phaseSeed), random(phaseSeed + 17), random(phaseSeed + 53), random(phaseSeed + 101), random(phaseSeed + 211)];
        const variant = cracks[phase][Math.floor(values[0] * cracks[phase].length)];
        const imageUrl = `url("${variant}")`;
        const position = `${(50 + values[1] * 8 - 4).toFixed(2)}% ${(50 + values[2] * 8 - 4).toFixed(2)}%`;
        const size = `${(110 + values[3] * 8).toFixed(2)}% ${(110 + values[3] * 8).toFixed(2)}%`;

        for (let copy = 0; copy < layerCounts[phase]; copy += 1) {
            backgrounds.push(imageUrl);
            positions.push(position);
            sizes.push(size);
        }
    }

    overlay.style.backgroundImage = backgrounds.join(', ');
    overlay.style.backgroundPosition = positions.join(', ');
    overlay.style.backgroundSize = sizes.join(', ');
}

window.addEventListener('message', (event) => {
    if (event.data && event.data.action === 'update') render(event.data);
});

fetch(`https://${GetParentResourceName()}/ready`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}'
}).catch(() => {});
