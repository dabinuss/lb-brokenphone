// Runs in lb-phone-damage's own NUI and renders into LB Phone's sibling frame.
(function () {
    'use strict';

    const assetRoot = window.LB_PHONE_DAMAGE_ASSET_ROOT || 'https://cfx-nui-lb-phone-damage/html/';
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
    const orientations = [
        { rotate: 0, scaleX: 1, scaleY: 1 },
        { rotate: 0, scaleX: -1, scaleY: 1 },
        { rotate: 0, scaleX: 1, scaleY: -1 },
        { rotate: 180, scaleX: 1, scaleY: 1 }
    ];
    const layerCounts = { 1: 3, 2: 2, 3: 1 };
    const crackFilterId = 'lb-phone-damage-levels';
    const phaseSeedStep = 1000003;

    let lastData = { damageLevel: 0, damageSeed: 0, state: 'closed' };
    let touchFaultActive = false;
    let renderToken = 0;
    let targetWindow = null;
    let targetDocument = null;
    let observedDocument = null;
    let targetObserver = null;
    const imageCache = new Map();
    const reportedLoadErrors = new Set();

    function resolveLbPhoneTarget() {
        try {
            const rootDocument = window.parent.document;
            const frames = Array.from(rootDocument.querySelectorAll('iframe'));
            const lbFrame = frames.find(function (frame) {
                return frame.name === 'lb-phone';
            }) || frames.find(function (frame) {
                return /(^|[-_/])lb-phone([/?#]|$)/i.test(frame.getAttribute('src') || frame.src || '');
            });

            if (lbFrame && lbFrame.contentWindow && lbFrame.contentDocument && lbFrame.contentDocument.body) {
                targetWindow = lbFrame.contentWindow;
                targetDocument = lbFrame.contentDocument;
                return true;
            }
        } catch (error) {
            // The retry loop below handles frames that are not ready yet.
        }

        targetWindow = null;
        targetDocument = null;
        return false;
    }

    function random(seed) {
        let value = (Number(seed) || 1) | 0;
        value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
        value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
        return ((value ^ (value >>> 16)) >>> 0) / 4294967296;
    }

    function ensureCrackFilter() {
        if (targetDocument.getElementById(crackFilterId)) return;

        const namespace = 'http://www.w3.org/2000/svg';
        const svg = targetDocument.createElementNS(namespace, 'svg');
        Object.assign(svg.style, {
            position: 'absolute',
            width: '0',
            height: '0',
            pointerEvents: 'none'
        });
        svg.setAttribute('aria-hidden', 'true');

        const filter = targetDocument.createElementNS(namespace, 'filter');
        filter.id = crackFilterId;
        filter.setAttribute('color-interpolation-filters', 'sRGB');

        const normalizeWhite = targetDocument.createElementNS(namespace, 'feComponentTransfer');
        normalizeWhite.setAttribute('result', 'normalized-white');
        const deepenCracks = targetDocument.createElementNS(namespace, 'feComponentTransfer');
        deepenCracks.setAttribute('in', 'normalized-white');

        for (const channel of ['R', 'G', 'B']) {
            const normalize = targetDocument.createElementNS(namespace, `feFunc${channel}`);
            normalize.setAttribute('type', 'linear');
            normalize.setAttribute('slope', '1.02');
            normalizeWhite.appendChild(normalize);

            const deepen = targetDocument.createElementNS(namespace, `feFunc${channel}`);
            deepen.setAttribute('type', 'gamma');
            deepen.setAttribute('amplitude', '1');
            deepen.setAttribute('exponent', '3');
            deepen.setAttribute('offset', '0');
            deepenCracks.appendChild(deepen);
        }

        filter.appendChild(normalizeWhite);
        filter.appendChild(deepenCracks);
        svg.appendChild(filter);
        targetDocument.documentElement.appendChild(svg);
    }

    function loadCrackImage(path) {
        const url = `${assetRoot}${path}`;
        if (!imageCache.has(url)) {
            imageCache.set(url, new Promise(function (resolve, reject) {
                const image = new Image();
                image.onload = function () { resolve(image); };
                image.onerror = function () { reject(new Error(`Failed to load ${url}`)); };
                image.src = url;
            }));
        }
        return imageCache.get(url);
    }

    function ensureOverlay() {
        if (!targetDocument && !resolveLbPhoneTarget()) return null;
        const phone = targetDocument.querySelector('.phone-container');
        if (!phone) return null;
        ensureCrackFilter();

        let overlay = targetDocument.getElementById('lb-phone-damage-overlay');
        if (overlay && overlay.parentElement !== phone) overlay.remove();
        if (!overlay || !overlay.isConnected) {
            overlay = targetDocument.createElement('div');
            overlay.id = 'lb-phone-damage-overlay';
            Object.assign(overlay.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '2147483646',
                borderRadius: 'inherit',
                overflow: 'hidden',
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

        overlay.style.backgroundImage = 'none';
        let canvas = overlay.querySelector('#lb-phone-damage-canvas');
        if (!canvas) {
            overlay.replaceChildren();
            canvas = targetDocument.createElement('canvas');
            canvas.id = 'lb-phone-damage-canvas';
            Object.assign(canvas.style, {
                display: 'block',
                width: '100%',
                height: '100%',
                pointerEvents: 'none'
            });
            overlay.appendChild(canvas);
        }
        return overlay;
    }

    async function composeDamage(canvas, level, seed, token) {
        const phases = [];
        for (let phase = 1; phase <= level; phase += 1) {
            if (!cracks[phase]) continue;
            const phaseSeed = seed + (phase - 1) * phaseSeedStep;
            const values = [random(phaseSeed), random(phaseSeed + 17), random(phaseSeed + 53), random(phaseSeed + 101), random(phaseSeed + 211)];
            const variant = cracks[phase][Math.floor(values[0] * cracks[phase].length)];
            const orientation = orientations[Math.floor(values[4] * orientations.length)];
            phases.push({
                phase,
                image: await loadCrackImage(variant),
                x: values[1] * 8 - 4,
                y: values[2] * 8 - 4,
                rotation: orientation.rotate + values[3] * 8 - 4,
                scale: 1.02 + values[1] * 0.10,
                scaleX: orientation.scaleX,
                scaleY: orientation.scaleY
            });
        }

        if (token !== renderToken || !canvas.isConnected) return;
        const overlay = canvas.parentElement;
        const pixelRatio = Math.min(Number(targetWindow && targetWindow.devicePixelRatio) || 1, 2);
        const width = Math.max(1, Math.round((overlay.clientWidth || 290) * pixelRatio));
        const height = Math.max(1, Math.round((overlay.clientHeight || 585) * pixelRatio));
        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;

        const context = canvas.getContext('2d');
        context.globalCompositeOperation = 'source-over';
        context.fillStyle = '#fff';
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = 'multiply';

        phases.forEach(function (phase) {
            const drawWidth = width * 1.2;
            const drawHeight = height * 1.2;
            context.save();
            context.translate(width * (0.5 + phase.x / 100), height * (0.5 + phase.y / 100));
            context.rotate(phase.rotation * Math.PI / 180);
            context.scale(phase.scale * phase.scaleX, phase.scale * phase.scaleY);
            for (let copy = 0; copy < layerCounts[phase.phase]; copy += 1) {
                context.drawImage(phase.image, -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight);
            }
            context.restore();
        });
        context.globalCompositeOperation = 'source-over';
        canvas.dataset.phases = String(phases.length);
        canvas.dataset.damageLevel = String(level);
        canvas.dataset.damageSeed = String(seed);
        canvas.dataset.transforms = JSON.stringify(phases.map(function (phase) {
            return [phase.phase, phase.x, phase.y, phase.rotation, phase.scale, phase.scaleX, phase.scaleY];
        }));
        overlay.style.display = 'block';
    }

    function render() {
        const overlay = ensureOverlay();
        if (!overlay) return;
        const canvas = overlay.querySelector('#lb-phone-damage-canvas');
        overlay.style.pointerEvents = touchFaultActive ? 'auto' : 'none';
        const level = Math.max(0, Math.min(3, Number(lastData.damageLevel) || 0));
        const seed = Number(lastData.damageSeed) || 1;
        const visible = level > 0 && lastData.state !== 'closed';
        renderToken += 1;
        if (!visible) {
            overlay.style.display = 'none';
            const context = canvas.getContext('2d');
            context.clearRect(0, 0, canvas.width, canvas.height);
            canvas.dataset.phases = '0';
            canvas.dataset.damageLevel = '0';
            canvas.dataset.damageSeed = '0';
            canvas.dataset.transforms = '[]';
            return;
        }

        const renderedLevel = Number(canvas.dataset.damageLevel) || 0;
        const renderedSeed = Number(canvas.dataset.damageSeed) || 0;
        const frameIsCompatible = renderedSeed === seed && renderedLevel > 0 && renderedLevel <= level;
        overlay.style.display = frameIsCompatible ? 'block' : 'none';
        const token = renderToken;
        composeDamage(canvas, level, seed, token).catch(function (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (reportedLoadErrors.has(message)) return;
            reportedLoadErrors.add(message);
            console.warn('[lb-phone-damage]', message);
        });
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

    fetch(`https://${GetParentResourceName()}/ready`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}'
    }).catch(function () {});

    function connectRenderer() {
        if (!resolveLbPhoneTarget()) return;
        if (observedDocument === targetDocument) return;

        if (targetObserver) targetObserver.disconnect();
        observedDocument = targetDocument;
        targetObserver = new MutationObserver(render);
        targetObserver.observe(targetDocument.documentElement, { childList: true, subtree: true });
        console.log('[lb-phone-damage][external] connected to lb-phone DOM');
        render();
    }

    connectRenderer();
    window.setInterval(connectRenderer, 1000);
})();
