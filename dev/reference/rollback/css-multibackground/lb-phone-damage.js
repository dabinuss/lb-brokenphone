(function () {
    'use strict';

    const assetRoot = 'https://cfx-nui-lb-phone-damage/html/';
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
            'cracks/medium/ChatGPT Image 9. Aug. 2026, 17_14_34.png',
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
    const crackFilterId = 'lb-phone-damage-levels';
    const phaseSeedStep = 1000003;

    let lastData = { damageLevel: 0, damageSeed: 0, state: 'closed' };
    let touchFaultActive = false;

    function random(seed) {
        let value = (Number(seed) || 1) | 0;
        value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
        value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
        return ((value ^ (value >>> 16)) >>> 0) / 4294967296;
    }

    function ensureCrackFilter() {
        if (document.getElementById(crackFilterId)) return;

        const namespace = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(namespace, 'svg');
        Object.assign(svg.style, {
            position: 'absolute',
            width: '0',
            height: '0',
            pointerEvents: 'none'
        });
        svg.setAttribute('aria-hidden', 'true');

        const filter = document.createElementNS(namespace, 'filter');
        filter.id = crackFilterId;
        filter.setAttribute('color-interpolation-filters', 'sRGB');

        const normalizeWhite = document.createElementNS(namespace, 'feComponentTransfer');
        normalizeWhite.setAttribute('result', 'normalized-white');
        const deepenCracks = document.createElementNS(namespace, 'feComponentTransfer');
        deepenCracks.setAttribute('in', 'normalized-white');

        for (const channel of ['R', 'G', 'B']) {
            const normalize = document.createElementNS(namespace, `feFunc${channel}`);
            normalize.setAttribute('type', 'linear');
            normalize.setAttribute('slope', '1.02');
            normalizeWhite.appendChild(normalize);

            const deepen = document.createElementNS(namespace, `feFunc${channel}`);
            deepen.setAttribute('type', 'gamma');
            deepen.setAttribute('amplitude', '1');
            deepen.setAttribute('exponent', '3');
            deepen.setAttribute('offset', '0');
            deepenCracks.appendChild(deepen);
        }

        filter.appendChild(normalizeWhite);
        filter.appendChild(deepenCracks);
        svg.appendChild(filter);
        document.documentElement.appendChild(svg);
    }

    function ensureOverlay() {
        const phone = document.querySelector('.phone-container');
        if (!phone) return null;
        ensureCrackFilter();

        let overlay = document.getElementById('lb-phone-damage-overlay');
        if (overlay && overlay.parentElement !== phone) overlay.remove();
        if (!overlay || !overlay.isConnected) {
            overlay = document.createElement('div');
            overlay.id = 'lb-phone-damage-overlay';
            Object.assign(overlay.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '2147483646',
                borderRadius: 'inherit',
                overflow: 'hidden',
                backgroundRepeat: 'no-repeat',
                backgroundBlendMode: 'multiply',
                filter: `url(#${crackFilterId})`,
                mixBlendMode: 'multiply',
                pointerEvents: 'none'
            });
            ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'touchstart', 'touchend'].forEach(function (type) {
                overlay.addEventListener(type, function (event) {
                    if (!touchFaultActive) return;
                    event.preventDefault();
                    event.stopImmediatePropagation();
                }, true);
            });
            phone.appendChild(overlay);
        }

        if (overlay.childElementCount > 0) overlay.replaceChildren();
        return overlay;
    }

    function render() {
        const overlay = ensureOverlay();
        if (!overlay) return;
        overlay.style.pointerEvents = touchFaultActive ? 'auto' : 'none';
        const level = Math.max(0, Math.min(3, Number(lastData.damageLevel) || 0));
        const visible = level > 0 && lastData.state !== 'closed';
        overlay.style.display = visible ? 'block' : 'none';
        if (!visible) {
            overlay.style.backgroundImage = 'none';
            return;
        }

        const seed = Number(lastData.damageSeed) || 1;
        const backgrounds = [];
        const positions = [];
        const sizes = [];

        for (let phase = 1; phase <= level; phase += 1) {
            if (!cracks[phase]) continue;
            const phaseSeed = seed + (phase - 1) * phaseSeedStep;
            const values = [random(phaseSeed), random(phaseSeed + 17), random(phaseSeed + 53), random(phaseSeed + 101), random(phaseSeed + 211)];
            const variant = cracks[phase][Math.floor(values[0] * cracks[phase].length)];
            const imageUrl = `url("${assetRoot}${variant}")`;
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

    window.addEventListener('message', function (event) {
        if (!event.data) return;
        if (event.data.action === 'lb-phone-damage:touchFault') {
            touchFaultActive = event.data.active === true;
            render();
            return;
        }
        if (event.data.action !== 'lb-phone-damage:update') return;
        lastData = event.data;
        render();
    });

    new MutationObserver(render).observe(document.documentElement, { childList: true, subtree: true });
    render();
})();
