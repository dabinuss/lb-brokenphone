// Runs in lb-brokenphone's own NUI and renders into LB Phone's sibling frame.
(function () {
    'use strict';

    const resourceName = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'lb-brokenphone';
    const assetRoot = window.LB_BROKENPHONE_ASSET_ROOT || `https://cfx-nui-${resourceName}/html/`;
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

    let lastData = {
        damageLevel: 0,
        damageSeed: 0,
        damageColor: 'black',
        state: 'closed',
        hackImage: 'hack/ahahah.gif',
        hackSound: 'hack/ahahah.ogg',
        hackSoundVolume: 0.65,
        hackSoundCooldown: 300
    };
    let touchFaultActive = false;
    let hackAudio = null;
    let hackAudioPath = null;
    let lastHackSoundAt = -Infinity;
    let hackWasVisible = false;
    let typeToken = 0;
    let renderToken = 0;
    let targetWindow = null;
    let targetDocument = null;
    let observedWindow = null;
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

    function assetUrl(path, fallback) {
        const relativePath = String(path || fallback).replace(/^\/+/, '');
        return `${assetRoot}${relativePath}`;
    }

    function hackActive() {
        return lastData.isHacked === true && lastData.state !== 'closed';
    }

    function startTypingEffect(element, text) {
        if (!text) {
            element.textContent = '';
            return;
        }
        typeToken++;
        const currentToken = typeToken;
        let i = 0;
        
        function typeNext() {
            if (currentToken !== typeToken || !hackActive()) return;
            
            element.textContent = text.slice(0, i);
            i++;
            
            if (i <= text.length) {
                setTimeout(typeNext, 80 + Math.random() * 70);
            } else {
                setTimeout(function() {
                    if (currentToken === typeToken && hackActive()) {
                        startTypingEffect(element, text);
                    }
                }, 2000);
            }
        }
        typeNext();
    }

    function stopHackSound() {
        if (!hackAudio) return;
        hackAudio.pause();
        hackAudio.currentTime = 0;
    }

    function playHackSound(force) {
        if (!hackActive()) return;
        const now = performance.now();
        const cooldown = Math.max(0, Number(lastData.hackSoundCooldown) || 0);
        if (!force && now - lastHackSoundAt < cooldown) return;
        lastHackSoundAt = now;

        const path = assetUrl(lastData.hackSound, 'hack/ahahah.ogg');
        if (!hackAudio || hackAudioPath !== path) {
            hackAudio = new Audio(path);
            hackAudio.preload = 'auto';
            hackAudioPath = path;
        }
        hackAudio.volume = Math.max(0, Math.min(1, Number(lastData.hackSoundVolume) || 0));
        hackAudio.currentTime = 0;
        hackAudio.play().catch(function () {});
    }

    function ensureOverlay(phone) {
        if (!targetDocument || !phone) return null;
        let overlay = targetDocument.getElementById('lb-brokenphone-overlay');
        if (overlay && overlay.parentElement !== phone) overlay.remove();
        if (!overlay || !overlay.isConnected) {
            overlay = targetDocument.createElement('div');
            overlay.id = 'lb-brokenphone-overlay';
            Object.assign(overlay.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '2147483646',
                borderRadius: 'inherit',
                overflow: 'hidden',
                filter: 'none',
                mixBlendMode: 'normal',
                pointerEvents: 'none'
            });
            ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'touchstart', 'touchend', 'wheel', 'contextmenu'].forEach(function (type) {
                overlay.addEventListener(type, function (event) {
                    if (!touchFaultActive && !hackActive()) return;
                    event.preventDefault();
                    event.stopImmediatePropagation();
                    if ((type === 'pointerdown' || type === 'mousedown' || type === 'touchstart') && hackActive()) {
                        playHackSound();
                    }
                }, true);
            });
            phone.appendChild(overlay);
        }

        // Re-apply geometry when adopting an overlay left behind by a resource restart.
        overlay.style.borderRadius = 'inherit';
        overlay.style.overflow = 'hidden';
        overlay.style.backgroundImage = 'none';
        let canvas = overlay.querySelector('#lb-brokenphone-canvas');
        if (!canvas) {
            canvas = targetDocument.createElement('canvas');
            canvas.id = 'lb-brokenphone-canvas';
            Object.assign(canvas.style, {
                display: 'block',
                position: 'absolute',
                inset: '0',
                zIndex: '4',
                width: '100%',
                height: '100%',
                pointerEvents: 'none'
            });
            overlay.appendChild(canvas);
        }
        let hackScreen = overlay.querySelector('#lb-brokenphone-hack');
        if (!hackScreen) {
            hackScreen = targetDocument.createElement('div');
            hackScreen.id = 'lb-brokenphone-hack';
            Object.assign(hackScreen.style, {
                position: 'absolute',
                inset: '0',
                display: 'none',
                alignItems: 'center',
                justifyContent: 'center',
                background: '#0b0d10',
                pointerEvents: 'none'
            });
            const hackImage = targetDocument.createElement('img');
            hackImage.id = 'lb-brokenphone-hack-image';
            hackImage.alt = '';
            hackImage.draggable = false;
            Object.assign(hackImage.style, {
                display: 'block',
                width: '50%',
                height: '50%',
                objectFit: 'contain',
                mixBlendMode: 'screen',
                pointerEvents: 'none',
                userSelect: 'none'
            });
            hackScreen.appendChild(hackImage);
            overlay.appendChild(hackScreen);
        }
        
        let hackText = hackScreen.querySelector('#lb-brokenphone-hack-text');
        if (!hackText) {
            hackText = targetDocument.createElement('div');
            hackText.id = 'lb-brokenphone-hack-text';
            Object.assign(hackText.style, {
                position: 'absolute',
                bottom: '18%',
                width: '100%',
                textAlign: 'center',
                color: '#00ff00',
                fontFamily: 'monospace',
                fontSize: '1.2rem',
                fontWeight: 'bold',
                textShadow: '0 0 3px #00ff00',
                whiteSpace: 'pre-wrap',
                zIndex: '3',
                pointerEvents: 'none',
                opacity: '1'
            });
            hackText.animate([
                { opacity: 1, transform: 'translate(0)' },
                { opacity: 0.8, transform: 'translate(-1px, 1px)' },
                { opacity: 1, transform: 'translate(1px, -1px)' },
                { opacity: 0.9, transform: 'translate(0)' }
            ], {
                duration: 150,
                iterations: Infinity,
                direction: 'alternate',
                easing: 'steps(2)'
            });
            hackScreen.appendChild(hackText);
        }
        
        let scanlines = hackScreen.querySelector('#lb-brokenphone-scanlines');
        if (!scanlines) {
            scanlines = targetDocument.createElement('div');
            scanlines.id = 'lb-brokenphone-scanlines';
            Object.assign(scanlines.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '2',
                backgroundImage: 'repeating-linear-gradient(to bottom, transparent 0, transparent 2px, rgba(0, 0, 0, 0.38) 3px, rgba(0, 0, 0, 0.38) 4px)',
                opacity: '0.8',
                pointerEvents: 'none'
            });
            scanlines.animate([
                { backgroundPosition: '0 0' },
                { backgroundPosition: '0 4px' }
            ], {
                duration: 1000,
                iterations: Infinity,
                easing: 'steps(60, end)'
            });
            hackScreen.appendChild(scanlines);
        }
        let movingScanline = hackScreen.querySelector('#lb-brokenphone-moving-scanline');
        if (!movingScanline) {
            movingScanline = targetDocument.createElement('div');
            movingScanline.id = 'lb-brokenphone-moving-scanline';
            Object.assign(movingScanline.style, {
                position: 'absolute',
                top: '-2px',
                left: '0',
                right: '0',
                height: '2px',
                zIndex: '3',
                background: 'rgba(0, 0, 0, 0.45)',
                boxShadow: '0 0 4px rgba(255, 255, 255, 0.08)',
                pointerEvents: 'none'
            });
            movingScanline.animate([
                { top: '-2px' },
                { top: '100%' }
            ], {
                duration: 6000,
                iterations: Infinity,
                easing: 'linear'
            });
            hackScreen.appendChild(movingScanline);
        }
        return overlay;
    }

    function removeOverlay() {
        const overlays = new Set([
            currentPhoneContainer?.querySelector('#lb-brokenphone-overlay'),
            observedDocument?.getElementById('lb-brokenphone-overlay'),
            targetDocument?.getElementById('lb-brokenphone-overlay')
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

    function blockHackKeyboard(event) {
        if (!hackActive()) return;
        event.preventDefault();
        event.stopImmediatePropagation();
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
                variant,
                x: values[1] * 8 - 4,
                y: values[2] * 8 - 4,
                rotation: orientation.rotate + values[3] * 8 - 4,
                scale: 1.02 + values[1] * 0.10,
                scaleX: orientation.scaleX,
                scaleY: orientation.scaleY
            });
        }

        const images = await Promise.all(phases.map(function (phase) {
            return loadCrackImage(phase.variant);
        }));
        phases.forEach(function (phase, index) {
            phase.image = images[index];
        });

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
        const canvas = overlay.querySelector('#lb-brokenphone-canvas');
        const hackScreen = overlay.querySelector('#lb-brokenphone-hack');
        const hackImage = hackScreen?.querySelector('#lb-brokenphone-hack-image');
        const hackTextEl = hackScreen?.querySelector('#lb-brokenphone-hack-text');
        const level = Math.max(0, Math.min(3, Number(lastData.damageLevel) || 0));
        const hacked = lastData.isHacked === true;
        overlay.style.pointerEvents = touchFaultActive || hacked ? 'auto' : 'none';
        const seed = Number(lastData.damageSeed) || 1;
        const damageColor = lastData.damageColor === 'white' ? 'white' : 'black';
        const visible = (level > 0 || hacked) && lastData.state !== 'closed';
        overlay.style.filter = 'none';
        overlay.style.mixBlendMode = hacked ? 'normal' : (damageColor === 'white' ? 'screen' : 'multiply');
        overlay.style.backgroundColor = 'transparent';
        canvas.style.mixBlendMode = hacked ? (damageColor === 'white' ? 'screen' : 'multiply') : 'normal';
        
        renderToken += 1;
        if (!visible) {
            hackWasVisible = false;
            overlay.style.display = 'none';
            canvas.style.display = 'none';
            if (hackScreen) hackScreen.style.display = 'none';
            stopHackSound();
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

        if (hacked) {
            if (!hackWasVisible) {
                playHackSound(true);
                if (hackTextEl) startTypingEffect(hackTextEl, lastData.hackText);
            }
            hackWasVisible = true;
            if (hackScreen) hackScreen.style.display = 'flex';
            if (hackImage) {
                const imageUrl = assetUrl(lastData.hackImage, 'hack/ahahah.gif');
                if (hackImage.src !== imageUrl) hackImage.src = imageUrl;
            }
        } else {
            hackWasVisible = false;
            if (hackScreen) hackScreen.style.display = 'none';
            stopHackSound();
        }

        if (level === 0) {
            canvas.style.display = 'none';
            overlay.style.display = 'block';
            return;
        }

        canvas.style.display = 'block';

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
            console.warn('[lb-brokenphone]', message);
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
        if (event.data.action === 'lb-brokenphone:touchFault') {
            touchFaultActive = event.data.active === true;
            scheduleRender();
            return;
        }
        if (event.data.action !== 'lb-brokenphone:update') return;
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
        observedWindow = targetWindow;
        observedDocument = targetDocument;
        ['keydown', 'keyup', 'keypress'].forEach(function (type) {
            targetWindow.addEventListener(type, blockHackKeyboard, true);
        });
        phoneHostObserver = new MutationObserver(checkPhoneContainer);
        phoneHostObserver.observe(targetDocument.documentElement, { childList: true, subtree: true });
        checkPhoneContainer();
    }

    function disconnectObservedDocument() {
        if (observedWindow) {
            ['keydown', 'keyup', 'keypress'].forEach(function (type) {
                observedWindow.removeEventListener(type, blockHackKeyboard, true);
            });
        }
        if (phoneHostObserver) phoneHostObserver.disconnect();
        phoneHostObserver = null;
        detachFromCurrentContainer();
        observedWindow = null;
        observedDocument = null;
    }

    function cleanup() {
        renderToken += 1;
        if (renderFrame !== null) window.cancelAnimationFrame(renderFrame);
        renderFrame = null;
        if (connectTimer !== null) window.clearInterval(connectTimer);
        connectTimer = null;
        stopHackSound();
        hackAudio = null;
        hackAudioPath = null;
        hackWasVisible = false;
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
