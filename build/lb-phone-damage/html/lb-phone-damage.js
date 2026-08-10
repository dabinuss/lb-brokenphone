// Runs in lb-phone-damage's own NUI and renders into LB Phone's sibling frame.
(function () {
    'use strict';

    const assetRoot = window.LB_PHONE_DAMAGE_ASSET_ROOT || 'https://cfx-nui-lb-phone-damage/html/';
    const cracks = {
        1: [
            'cracks/light/cracklight1.webp',
            'cracks/light/cracklight2.webp',
            'cracks/light/cracklight3.webp',
            'cracks/light/cracklight4.webp',
            'cracks/light/cracklight5.webp',
            'cracks/light/cracklight6.webp',
            'cracks/light/cracklight7.webp'
        ],
        2: [
            'cracks/medium/crackmedium1.webp',
            'cracks/medium/crackmedium2.webp',
            'cracks/medium/crackmedium3.webp',
            'cracks/medium/crackmedium4.webp',
            'cracks/medium/crackmedium5.webp',
            'cracks/medium/crackmedium6.webp',
            'cracks/medium/crackmedium7.webp'
        ],
        3: [
            'cracks/severe/cracksevere1.webp',
            'cracks/severe/cracksevere2.webp',
            'cracks/severe/cracksevere3.webp',
            'cracks/severe/cracksevere4.webp',
            'cracks/severe/cracksevere5.webp',
            'cracks/severe/cracksevere6.webp',
            'cracks/severe/cracksevere7.webp'
        ]
    };
    const orientations = [
        { rotate: 0, scaleX: 1, scaleY: 1 },
        { rotate: 0, scaleX: -1, scaleY: 1 },
        { rotate: 0, scaleX: 1, scaleY: -1 },
        { rotate: 180, scaleX: 1, scaleY: 1 }
    ];
    const layerCounts = { 1: 3, 2: 2, 3: 1 };
    const phaseSeedStep = 1000003;
    const crackLevels = Uint8Array.from({ length: 256 }, function (_, value) {
        const normalized = Math.min(255, value * 1.02) / 255;
        return Math.round(normalized * normalized * normalized * 255);
    });

    let lastData = { damageLevel: 0, damageSeed: 0, damageColor: 'black', state: 'closed' };
    let touchFaultActive = false;
    let renderToken = 0;
    let targetWindow = null;
    let targetDocument = null;
    let observedDocument = null;
    let currentPhoneContainer = null;
    let phoneHostObserver = null;
    let resizeObserver = null;
    let renderFrame = null;
    let connectTimer = null;
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

    function getPhoneContainer() {
        return targetDocument?.querySelector('.phone-container') || null;
    }

    function ensureOverlay(phone) {
        if (!targetDocument || !phone) return null;
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
                filter: 'none',
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

        // Re-apply geometry when adopting an overlay left behind by a resource restart.
        overlay.style.borderRadius = 'inherit';
        overlay.style.overflow = 'hidden';
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

    function removeOverlay() {
        const overlays = new Set([
            currentPhoneContainer?.querySelector('#lb-phone-damage-overlay'),
            observedDocument?.getElementById('lb-phone-damage-overlay'),
            targetDocument?.getElementById('lb-phone-damage-overlay')
        ]);
        overlays.forEach(function (overlay) {
            overlay?.remove();
        });
    }

    function detachFromCurrentContainer() {
        if (resizeObserver) resizeObserver.disconnect();
        resizeObserver = null;
        removeOverlay();
        currentPhoneContainer = null;
    }

    function attachToPhoneContainer(container) {
        ensureOverlay(container);
        resizeObserver = new ResizeObserver(scheduleRender);
        resizeObserver.observe(container);
    }

    function checkPhoneContainer() {
        const nextContainer = getPhoneContainer();
        if (nextContainer === currentPhoneContainer) return;

        detachFromCurrentContainer();
        currentPhoneContainer = nextContainer;
        if (!currentPhoneContainer) return;

        attachToPhoneContainer(currentPhoneContainer);
        scheduleRender();
    }

    async function composeDamage(canvas, level, seed, damageColor, token, width, height) {
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
        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;

        const context = canvas.getContext('2d');
        context.globalCompositeOperation = 'source-over';
        context.fillStyle = '#fff';
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = 'multiply';

        phases.forEach(function (phase) {
            // Keep the image edges outside the display even after rotation and
            // random offsets. The tall phone aspect ratio needs extra width.
            const drawWidth = width * 1.5;
            const drawHeight = height * 1.35;
            context.save();
            context.translate(width * (0.5 + phase.x / 100), height * (0.5 + phase.y / 100));
            context.rotate(phase.rotation * Math.PI / 180);
            context.scale(phase.scale * phase.scaleX, phase.scale * phase.scaleY);
            for (let copy = 0; copy < layerCounts[phase.phase]; copy += 1) {
                context.drawImage(phase.image, -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight);
            }
            context.restore();
        });

        // Apply contrast and color conversion directly to the canvas pixels.
        const imageData = context.getImageData(0, 0, width, height);
        const pixels = imageData.data;
        for (let index = 0; index < pixels.length; index += 4) {
            const red = crackLevels[pixels[index]];
            const green = crackLevels[pixels[index + 1]];
            const blue = crackLevels[pixels[index + 2]];
            pixels[index] = damageColor === 'white' ? 255 - red : red;
            pixels[index + 1] = damageColor === 'white' ? 255 - green : green;
            pixels[index + 2] = damageColor === 'white' ? 255 - blue : blue;
        }
        context.putImageData(imageData, 0, 0);
        context.globalCompositeOperation = 'source-over';
        canvas.dataset.phases = String(phases.length);
        canvas.dataset.damageLevel = String(level);
        canvas.dataset.damageSeed = String(seed);
        canvas.dataset.damageColor = String(damageColor);
        canvas.dataset.width = String(width);
        canvas.dataset.height = String(height);
        canvas.dataset.transforms = JSON.stringify(phases.map(function (phase) {
            return [phase.phase, phase.x, phase.y, phase.rotation, phase.scale, phase.scaleX, phase.scaleY];
        }));
        overlay.style.display = 'block';
    }

    function render() {
        const overlay = ensureOverlay(currentPhoneContainer);
        if (!overlay) return;
        const canvas = overlay.querySelector('#lb-phone-damage-canvas');
        overlay.style.pointerEvents = touchFaultActive ? 'auto' : 'none';
        const level = Math.max(0, Math.min(3, Number(lastData.damageLevel) || 0));
        const seed = Number(lastData.damageSeed) || 1;
        const damageColor = lastData.damageColor === 'white' ? 'white' : 'black';
        overlay.style.filter = 'none';
        overlay.style.mixBlendMode = damageColor === 'white' ? 'screen' : 'multiply';
        const visible = level > 0 && lastData.state !== 'closed';
        renderToken += 1;
        if (!visible) {
            overlay.style.display = 'none';
            const context = canvas.getContext('2d');
            context.clearRect(0, 0, canvas.width, canvas.height);
            canvas.dataset.phases = '0';
            canvas.dataset.damageLevel = '0';
            canvas.dataset.damageSeed = '0';
            canvas.dataset.damageColor = String(damageColor);
            canvas.dataset.width = '0';
            canvas.dataset.height = '0';
            canvas.dataset.transforms = '[]';
            return;
        }

        const pixelRatio = Math.min(Number(targetWindow && targetWindow.devicePixelRatio) || 1, 2);
        const displayWidth = overlay.parentElement.clientWidth || overlay.clientWidth || 290;
        const displayHeight = overlay.parentElement.clientHeight || overlay.clientHeight || 585;
        const width = Math.max(1, Math.round(displayWidth * pixelRatio));
        const height = Math.max(1, Math.round(displayHeight * pixelRatio));
        const renderedLevel = Number(canvas.dataset.damageLevel) || 0;
        const renderedSeed = Number(canvas.dataset.damageSeed) || 0;
        const renderedColor = canvas.dataset.damageColor || 'black';
        const renderedWidth = Number(canvas.dataset.width) || 0;
        const renderedHeight = Number(canvas.dataset.height) || 0;
        const exactMatch = renderedLevel === level
            && renderedSeed === seed
            && renderedColor === damageColor
            && renderedWidth === width
            && renderedHeight === height;
        if (exactMatch) {
            overlay.style.display = 'block';
            return;
        }

        const frameIsCompatible = renderedSeed === seed
            && renderedColor === damageColor
            && renderedWidth === width
            && renderedHeight === height
            && renderedLevel > 0
            && renderedLevel <= level;
        overlay.style.display = frameIsCompatible ? 'block' : 'none';
        const token = renderToken;
        composeDamage(canvas, level, seed, damageColor, token, width, height).catch(function (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (reportedLoadErrors.has(message)) return;
            reportedLoadErrors.add(message);
            console.warn('[lb-phone-damage]', message);
        });
    }

    function scheduleRender() {
        if (renderFrame !== null) return;
        renderFrame = window.requestAnimationFrame(function () {
            renderFrame = null;
            render();
        });
    }

    window.addEventListener('message', function (event) {
        if (!event.data) return;
        if (event.data.action === 'lb-phone-damage:touchFault') {
            touchFaultActive = event.data.active === true;
            scheduleRender();
            return;
        }
        if (event.data.action !== 'lb-phone-damage:update') return;
        lastData = event.data;
        scheduleRender();
    });

    fetch(`https://${GetParentResourceName()}/ready`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}'
    }).catch(function () {});

    function connectRenderer() {
        if (!resolveLbPhoneTarget()) {
            if (observedDocument) disconnectObservedDocument();
            return;
        }
        if (observedDocument === targetDocument) {
            checkPhoneContainer();
            return;
        }

        disconnectObservedDocument();
        observedDocument = targetDocument;
        phoneHostObserver = new MutationObserver(checkPhoneContainer);
        phoneHostObserver.observe(targetDocument.documentElement, { childList: true, subtree: true });
        console.log('[lb-phone-damage][external] connected to lb-phone DOM');
        checkPhoneContainer();
    }

    function disconnectObservedDocument() {
        if (phoneHostObserver) phoneHostObserver.disconnect();
        phoneHostObserver = null;
        detachFromCurrentContainer();
        observedDocument = null;
    }

    function cleanup() {
        renderToken += 1;
        if (renderFrame !== null) window.cancelAnimationFrame(renderFrame);
        renderFrame = null;
        if (connectTimer !== null) window.clearInterval(connectTimer);
        connectTimer = null;
        disconnectObservedDocument();
        removeOverlay();
        targetDocument = null;
        targetWindow = null;
    }

    connectRenderer();
    connectTimer = window.setInterval(connectRenderer, 1000);
    window.addEventListener('pagehide', cleanup);
    window.addEventListener('beforeunload', cleanup);
})();
