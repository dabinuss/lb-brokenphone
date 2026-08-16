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
    const crackEdge = {
        shadowOffsetX: 1.4,
        shadowOffsetY: 1.9,
        shadowBlur: 1.55,
        shadowOpacity: 0.58,
        highlightOffsetX: -0.55,
        highlightOffsetY: -0.7,
        highlightBlur: 0.35,
        highlightOpacity: 0.23
    };
    const phaseSeedStep = 1000003;
    const crackLevels = Uint8Array.from({ length: 256 }, function (_, value) {
        const normalized = Math.min(255, value * 1.02) / 255;
        return Math.round(normalized * normalized * normalized * 255);
    });

    let lastData = {
        damageLevel: 0,
        damageSeed: 0,
        fireLevel: 0,
        fireSeed: 0,
        fireImages: { light: [], medium: [] },
        fireBlockInput: true,
        fireInputBlockThreshold: 0.62,
        damageColor: 'black',
        state: 'closed',
        hackImage: 'hack/ahahah.gif',
        hackSound: 'hack/ahahah.ogg',
        hackSoundVolume: 0.65,
        hackSoundCooldown: 300,
        hackStartDuration: 5500,
        hackEndDuration: 5500,
        hackActiveGlitchIntervalMin: 2000,
        hackActiveGlitchIntervalMax: 5000,
        hackActiveGlitchDurationMin: 50,
        hackActiveGlitchDurationMax: 120
    };
    let touchFaultActive = false;
    let hackAudio = null;
    let hackAudioPath = null;
    let lastHackSoundAt = -Infinity;
    let hackPhase = 'idle';
    let hackPhaseToken = 0;
    const hackTimers = new Set();
    const hackAnimations = new Set();
    let fireInputMask = null;
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
    let resizeTimer = null;
    let phoneCheckFrame = null;
    let connectTimer = null;
    const PHONE_CONTAINER_SELECTORS = ['.phone-container'];
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

    function loadAssetImage(path) {
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

    const loadCrackImage = loadAssetImage;

    function getPhoneContainer() {
        if (!targetDocument) return null;
        for (const selector of PHONE_CONTAINER_SELECTORS) {
            const container = targetDocument.querySelector(selector);
            if (container) return container;
        }
        return null;
    }

    function assetUrl(path, fallback) {
        const relativePath = String(path || fallback).replace(/^\/+/, '');
        return `${assetRoot}${relativePath}`;
    }

    function hackActive() {
        return hackPhase !== 'idle' && lastData.state !== 'closed';
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
        let shadowCanvas = overlay.querySelector('#lb-brokenphone-crack-shadow');
        if (!shadowCanvas) {
            shadowCanvas = targetDocument.createElement('canvas');
            shadowCanvas.id = 'lb-brokenphone-crack-shadow';
            Object.assign(shadowCanvas.style, {
                display: 'block',
                position: 'absolute',
                inset: '0',
                zIndex: '2',
                width: '100%',
                height: '100%',
                opacity: String(crackEdge.shadowOpacity),
                filter: `blur(${crackEdge.shadowBlur}px)`,
                transform: `translate(${crackEdge.shadowOffsetX}px, ${crackEdge.shadowOffsetY}px)`,
                mixBlendMode: 'multiply',
                pointerEvents: 'none'
            });
            overlay.appendChild(shadowCanvas);
        }
        let highlightCanvas = overlay.querySelector('#lb-brokenphone-crack-highlight');
        if (!highlightCanvas) {
            highlightCanvas = targetDocument.createElement('canvas');
            highlightCanvas.id = 'lb-brokenphone-crack-highlight';
            Object.assign(highlightCanvas.style, {
                display: 'block',
                position: 'absolute',
                inset: '0',
                zIndex: '3',
                width: '100%',
                height: '100%',
                opacity: String(crackEdge.highlightOpacity),
                filter: `blur(${crackEdge.highlightBlur}px)`,
                transform: `translate(${crackEdge.highlightOffsetX}px, ${crackEdge.highlightOffsetY}px)`,
                mixBlendMode: 'screen',
                pointerEvents: 'none'
            });
            overlay.appendChild(highlightCanvas);
        }
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
        let fireCanvas = overlay.querySelector('#lb-brokenphone-fire');
        if (!fireCanvas) {
            fireCanvas = targetDocument.createElement('canvas');
            fireCanvas.id = 'lb-brokenphone-fire';
            Object.assign(fireCanvas.style, {
                display: 'none',
                position: 'absolute',
                inset: '0',
                zIndex: '5',
                width: '100%',
                height: '100%',
                mixBlendMode: 'multiply',
                pointerEvents: 'none'
            });
            overlay.appendChild(fireCanvas);
        }
        let hackScreen = overlay.querySelector('#lb-brokenphone-hack');
        if (!hackScreen) {
            hackScreen = targetDocument.createElement('div');
            hackScreen.id = 'lb-brokenphone-hack';
            Object.assign(hackScreen.style, {
                position: 'absolute',
                inset: '0',
                display: 'none',
                zIndex: '1',
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
        let glitchFx = hackScreen.querySelector('#lb-brokenphone-hack-glitch-fx');
        if (!glitchFx) {
            glitchFx = targetDocument.createElement('div');
            glitchFx.id = 'lb-brokenphone-hack-glitch-fx';
            Object.assign(glitchFx.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '4',
                opacity: '0',
                backgroundImage: 'repeating-linear-gradient(90deg, rgba(255, 0, 68, 0.2) 0 2px, transparent 2px 7px, rgba(0, 220, 255, 0.18) 7px 9px, transparent 9px 15px)',
                backgroundSize: '19px 100%',
                mixBlendMode: 'screen',
                pointerEvents: 'none',
                willChange: 'opacity, transform, background-position'
            });
            hackScreen.appendChild(glitchFx);
        }
        let glitchSlices = hackScreen.querySelector('#lb-brokenphone-hack-glitch-slices');
        if (!glitchSlices) {
            glitchSlices = targetDocument.createElement('div');
            glitchSlices.id = 'lb-brokenphone-hack-glitch-slices';
            Object.assign(glitchSlices.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '5',
                overflow: 'hidden',
                pointerEvents: 'none'
            });
            for (let index = 0; index < 5; index += 1) {
                const slice = targetDocument.createElement('div');
                slice.className = 'lb-brokenphone-hack-glitch-slice';
                Object.assign(slice.style, {
                    position: 'absolute',
                    left: '-6%',
                    width: '112%',
                    opacity: '0',
                    background: index % 2 === 0
                        ? 'rgba(0, 220, 255, 0.12)'
                        : 'rgba(255, 0, 68, 0.12)',
                    mixBlendMode: 'screen',
                    pointerEvents: 'none',
                    willChange: 'opacity, transform, clip-path'
                });
                glitchSlices.appendChild(slice);
            }
            hackScreen.appendChild(glitchSlices);
        }
        let blackout = hackScreen.querySelector('#lb-brokenphone-hack-blackout');
        if (!blackout) {
            blackout = targetDocument.createElement('div');
            blackout.id = 'lb-brokenphone-hack-blackout';
            Object.assign(blackout.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '6',
                opacity: '0',
                background: '#000',
                pointerEvents: 'none',
                willChange: 'opacity'
            });
            hackScreen.appendChild(blackout);
        }
        let flash = hackScreen.querySelector('#lb-brokenphone-hack-flash');
        if (!flash) {
            flash = targetDocument.createElement('div');
            flash.id = 'lb-brokenphone-hack-flash';
            Object.assign(flash.style, {
                position: 'absolute',
                inset: '0',
                zIndex: '7',
                opacity: '0',
                background: '#dffcff',
                mixBlendMode: 'screen',
                pointerEvents: 'none',
                willChange: 'opacity'
            });
            hackScreen.appendChild(flash);
        }
        return overlay;
    }

    function getHackElements() {
        const overlay = currentPhoneContainer?.querySelector('#lb-brokenphone-overlay');
        const screen = overlay?.querySelector('#lb-brokenphone-hack');
        return {
            screen: screen,
            image: screen?.querySelector('#lb-brokenphone-hack-image'),
            text: screen?.querySelector('#lb-brokenphone-hack-text'),
            fx: screen?.querySelector('#lb-brokenphone-hack-glitch-fx'),
            slices: Array.from(screen?.querySelectorAll('.lb-brokenphone-hack-glitch-slice') || []),
            blackout: screen?.querySelector('#lb-brokenphone-hack-blackout'),
            flash: screen?.querySelector('#lb-brokenphone-hack-flash')
        };
    }

    function trackHackAnimation(animation) {
        if (!animation) return null;
        hackAnimations.add(animation);
        const forget = function () { hackAnimations.delete(animation); };
        animation.onfinish = forget;
        animation.oncancel = forget;
        return animation;
    }

    function animateHackElement(element, keyframes, options) {
        if (!element || typeof element.animate !== 'function') return null;
        return trackHackAnimation(element.animate(keyframes, options));
    }

    function clearHackTimers() {
        hackTimers.forEach(function (timer) { window.clearTimeout(timer); });
        hackTimers.clear();
    }

    function clearHackAnimations() {
        Array.from(hackAnimations).forEach(function (animation) { animation.cancel(); });
        hackAnimations.clear();
    }

    function resetHackVisuals() {
        const elements = getHackElements();
        if (elements.screen) {
            elements.screen.style.opacity = '1';
            elements.screen.style.transform = 'none';
            elements.screen.style.filter = 'none';
        }
        if (elements.image) {
            elements.image.style.opacity = '1';
            elements.image.style.transform = 'none';
            elements.image.style.filter = 'none';
        }
        if (elements.text) {
            elements.text.style.filter = 'none';
            elements.text.style.textShadow = '0 0 3px #00ff00';
        }
        if (elements.fx) {
            elements.fx.style.opacity = '0';
            elements.fx.style.transform = 'none';
        }
        elements.slices.forEach(function (slice) {
            slice.style.opacity = '0';
            slice.style.transform = 'none';
        });
        if (elements.blackout) elements.blackout.style.opacity = '0';
        if (elements.flash) elements.flash.style.opacity = '0';
    }

    function invalidateHackRuntime() {
        hackPhaseToken += 1;
        clearHackTimers();
        clearHackAnimations();
        resetHackVisuals();
        return hackPhaseToken;
    }

    function scheduleHackTask(token, delay, callback) {
        const timer = window.setTimeout(function () {
            hackTimers.delete(timer);
            if (token !== hackPhaseToken) return;
            callback();
        }, Math.max(0, delay));
        hackTimers.add(timer);
        return timer;
    }

    function randomBetween(minimum, maximum) {
        return minimum + Math.random() * Math.max(0, maximum - minimum);
    }

    function runHackGlitchBurst(duration, strength) {
        const elements = getHackElements();
        if (!elements.screen) return;
        duration = Math.max(25, Number(duration) || 80);
        strength = Math.max(0.25, Number(strength) || 1);
        const offsetX = Math.round(randomBetween(2, 5) * strength);
        const offsetY = Math.max(1, Math.round(randomBetween(0.5, 2) * strength));
        const skew = randomBetween(0.4, 1.4) * strength;

        animateHackElement(elements.screen, [
            { transform: 'translate(0, 0)', filter: 'none', offset: 0 },
            { transform: `translate(${-offsetX}px, ${offsetY}px) skewX(${skew}deg)`, filter: `contrast(${1 + strength * 0.35}) brightness(${1 + strength * 0.12})`, offset: 0.25 },
            { transform: `translate(${offsetX}px, ${-offsetY}px) skewX(${-skew}deg)`, filter: `contrast(${1 + strength * 0.55}) brightness(${Math.max(0.65, 1 - strength * 0.12)})`, offset: 0.62 },
            { transform: 'translate(0, 0)', filter: 'none', offset: 1 }
        ], { duration: duration, easing: 'steps(3, end)' });

        animateHackElement(elements.image, [
            { transform: 'translate(0, 0)', filter: 'none' },
            { transform: `translateX(${offsetX}px) scaleX(${1 + strength * 0.015})`, filter: `drop-shadow(${-offsetX}px 0 rgba(255, 0, 68, 0.9)) drop-shadow(${offsetX}px 0 rgba(0, 220, 255, 0.9)) saturate(${1 + strength * 0.8})` },
            { transform: `translateX(${-offsetX}px) scaleY(${1 + strength * 0.01})`, filter: `drop-shadow(${offsetX}px 0 rgba(255, 0, 68, 0.75)) drop-shadow(${-offsetX}px 0 rgba(0, 220, 255, 0.75))` },
            { transform: 'translate(0, 0)', filter: 'none' }
        ], { duration: duration, easing: 'steps(2, end)' });

        animateHackElement(elements.text, [
            { filter: 'none', textShadow: '0 0 3px #00ff00' },
            { filter: `contrast(${1 + strength})`, textShadow: `${-offsetX}px 0 rgba(255, 0, 68, 0.9), ${offsetX}px 0 rgba(0, 220, 255, 0.9), 0 0 5px #00ff00` },
            { filter: 'none', textShadow: '0 0 3px #00ff00' }
        ], { duration: duration, easing: 'steps(2, end)' });

        animateHackElement(elements.fx, [
            { opacity: 0, transform: 'translateX(0)', backgroundPosition: '0 0' },
            { opacity: Math.min(0.9, 0.3 + strength * 0.22), transform: `translateX(${offsetX}px)`, backgroundPosition: `${offsetX * 3}px 0` },
            { opacity: Math.min(0.75, 0.2 + strength * 0.18), transform: `translateX(${-offsetX}px)`, backgroundPosition: `${-offsetX * 2}px 0` },
            { opacity: 0, transform: 'translateX(0)', backgroundPosition: '0 0' }
        ], { duration: duration, easing: 'steps(3, end)' });

        elements.slices.forEach(function (slice, index) {
            const top = randomBetween(4, 91);
            const height = randomBetween(1.5, 7) * Math.min(1.6, strength);
            const direction = index % 2 === 0 ? 1 : -1;
            const travel = direction * Math.round(randomBetween(5, 14) * strength);
            slice.style.top = `${top}%`;
            slice.style.height = `${height}%`;
            slice.style.clipPath = `polygon(0 ${randomBetween(0, 18)}%, 100% 0, 98% 100%, 2% ${randomBetween(82, 100)}%)`;
            slice.style.backdropFilter = `hue-rotate(${direction * 35 * strength}deg) saturate(${1 + strength}) contrast(${1 + strength * 0.4})`;
            slice.style.webkitBackdropFilter = slice.style.backdropFilter;
            animateHackElement(slice, [
                { opacity: 0, transform: 'translateX(0)' },
                { opacity: Math.min(0.85, 0.28 + strength * 0.2), transform: `translateX(${travel}px)` },
                { opacity: Math.min(0.65, 0.2 + strength * 0.15), transform: `translateX(${-travel * 0.6}px)` },
                { opacity: 0, transform: 'translateX(0)' }
            ], { duration: duration * randomBetween(0.75, 1.15), easing: 'steps(2, end)' });
        });
    }

    function runHackBlackout(duration) {
        const blackout = getHackElements().blackout;
        animateHackElement(blackout, [
            { opacity: 0 },
            { opacity: 1, offset: 0.12 },
            { opacity: 1, offset: 0.78 },
            { opacity: 0 }
        ], { duration: Math.max(100, duration), easing: 'steps(2, end)' });
    }

    function runHackFlash(duration) {
        const flash = getHackElements().flash;
        animateHackElement(flash, [
            { opacity: 0 },
            { opacity: 0.8, offset: 0.18 },
            { opacity: 0.16, offset: 0.42 },
            { opacity: 0 }
        ], { duration: Math.max(100, duration), easing: 'ease-out' });
    }

    function scheduleActiveHackGlitch(token) {
        if (token !== hackPhaseToken || hackPhase !== 'active') return;
        const minimum = Math.max(250, Number(lastData.hackActiveGlitchIntervalMin) || 2000);
        const maximum = Math.max(minimum, Number(lastData.hackActiveGlitchIntervalMax) || 5000);
        scheduleHackTask(token, randomBetween(minimum, maximum), function () {
            if (hackPhase !== 'active' || lastData.isHacked !== true || lastData.state === 'closed') return;
            const durationMinimum = Math.max(25, Number(lastData.hackActiveGlitchDurationMin) || 50);
            const durationMaximum = Math.max(durationMinimum, Number(lastData.hackActiveGlitchDurationMax) || 120);
            runHackGlitchBurst(randomBetween(durationMinimum, durationMaximum), randomBetween(0.9, 1.55));
            scheduleActiveHackGlitch(token);
        });
    }

    function enterActiveHack(token) {
        if (token !== hackPhaseToken || lastData.isHacked !== true || lastData.state === 'closed') return;
        clearHackTimers();
        clearHackAnimations();
        resetHackVisuals();
        hackPhase = 'active';
        scheduleActiveHackGlitch(token);
        scheduleRender();
    }

    function startHackIntroduction() {
        const token = invalidateHackRuntime();
        const elements = getHackElements();
        if (!elements.screen) return;
        hackPhase = 'starting';
        elements.screen.style.display = 'flex';
        playHackSound(true);
        if (elements.text) startTypingEffect(elements.text, lastData.hackText);

        const duration = Math.max(1000, Number(lastData.hackStartDuration) || 5500);
        const scale = duration / 5500;
        [
            [0, 420, 0.75],
            [900, 520, 1.0],
            [1900, 600, 1.25],
            [3000, 700, 1.55],
            [4000, 650, 1.9]
        ].forEach(function (burst) {
            scheduleHackTask(token, burst[0] * scale, function () {
                runHackGlitchBurst(burst[1] * scale, burst[2]);
            });
        });
        scheduleHackTask(token, 4550 * scale, function () { runHackBlackout(500 * scale); });
        scheduleHackTask(token, 5050 * scale, function () { runHackGlitchBurst(380 * scale, 1.15); });
        scheduleHackTask(token, duration, function () { enterActiveHack(token); });
    }

    function finishHackEnding(token) {
        if (token !== hackPhaseToken) return;
        clearHackTimers();
        clearHackAnimations();
        resetHackVisuals();
        hackPhase = 'idle';
        typeToken += 1;
        const screen = getHackElements().screen;
        if (screen) screen.style.display = 'none';
        stopHackSound();
        scheduleRender();
    }

    function startHackEnding() {
        const token = invalidateHackRuntime();
        const elements = getHackElements();
        if (!elements.screen) return;
        hackPhase = 'ending';
        typeToken += 1;
        elements.screen.style.display = 'flex';

        const duration = Math.max(1000, Number(lastData.hackEndDuration) || 5500);
        const scale = duration / 5500;
        [
            [0, 450, 0.85],
            [1100, 560, 1.1],
            [2200, 650, 1.4],
            [3300, 760, 1.85]
        ].forEach(function (burst) {
            scheduleHackTask(token, burst[0] * scale, function () {
                runHackGlitchBurst(burst[1] * scale, burst[2]);
            });
        });
        scheduleHackTask(token, 4100 * scale, function () { runHackBlackout(700 * scale); });
        scheduleHackTask(token, 4750 * scale, function () {
            runHackFlash(650 * scale);
            animateHackElement(elements.screen, [
                { opacity: 1, filter: 'brightness(1)' },
                { opacity: 0.82, filter: 'brightness(1.8)', offset: 0.2 },
                { opacity: 0, filter: 'brightness(1.15)' }
            ], { duration: 750 * scale, easing: 'ease-out' });
        });
        scheduleHackTask(token, duration, function () { finishHackEnding(token); });
    }

    function stopHackImmediately() {
        invalidateHackRuntime();
        hackPhase = 'idle';
        typeToken += 1;
        const screen = getHackElements().screen;
        if (screen) screen.style.display = 'none';
        stopHackSound();
    }

    function syncHackPhase(phoneVisible) {
        if (!phoneVisible) {
            if (hackPhase !== 'idle') stopHackImmediately();
            return;
        }
        if (lastData.isHacked === true) {
            if (hackPhase === 'idle' || hackPhase === 'ending') startHackIntroduction();
        } else if (hackPhase === 'starting' || hackPhase === 'active') {
            startHackEnding();
        }
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
        if (hackPhase !== 'idle') stopHackImmediately();
        if (resizeObserver) resizeObserver.disconnect();
        resizeObserver = null;
        if (resizeTimer !== null) window.clearTimeout(resizeTimer);
        resizeTimer = null;
        fireInputMask = null;
        removeOverlay();
        currentPhoneContainer = null;
    }

    function attachToPhoneContainer(container) {
        ensureOverlay(container);
        resizeObserver = new ResizeObserver(function () {
            if (resizeTimer !== null) window.clearTimeout(resizeTimer);
            resizeTimer = window.setTimeout(function () {
                resizeTimer = null;
                scheduleRender();
            }, 75);
        });
        resizeObserver.observe(container);
    }

    function blockHackKeyboard(event) {
        if (!hackActive()) return;
        event.preventDefault();
        event.stopImmediatePropagation();
    }

    function getEventPoint(event) {
        const touch = event.touches?.[0] || event.changedTouches?.[0];
        if (touch) return { x: touch.clientX, y: touch.clientY };
        if (!Number.isFinite(event.clientX) || !Number.isFinite(event.clientY)) return null;
        return { x: event.clientX, y: event.clientY };
    }

    function hitsBlockedFirePixel(event) {
        if (!fireInputMask || lastData.fireBlockInput !== true || lastData.state === 'closed') return false;
        const phone = currentPhoneContainer;
        const point = getEventPoint(event);
        if (!phone || !point) return false;

        const rect = phone.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0
            || point.x < rect.left || point.x >= rect.right
            || point.y < rect.top || point.y >= rect.bottom) return false;

        const x = Math.min(fireInputMask.width - 1,
            Math.max(0, Math.floor((point.x - rect.left) / rect.width * fireInputMask.width)));
        const y = Math.min(fireInputMask.height - 1,
            Math.max(0, Math.floor((point.y - rect.top) / rect.height * fireInputMask.height)));
        return fireInputMask.pixels[y * fireInputMask.width + x] === 1;
    }

    function blockDamagedInput(event) {
        if (!hitsBlockedFirePixel(event)) return;
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

    function schedulePhoneContainerCheck() {
        if (phoneCheckFrame !== null) return;
        phoneCheckFrame = window.requestAnimationFrame(function () {
            phoneCheckFrame = null;
            checkPhoneContainer();
        });
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
        const shadowCanvas = overlay.querySelector('#lb-brokenphone-crack-shadow');
        const highlightCanvas = overlay.querySelector('#lb-brokenphone-crack-highlight');
        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;
        if (shadowCanvas.width !== width) shadowCanvas.width = width;
        if (shadowCanvas.height !== height) shadowCanvas.height = height;
        if (highlightCanvas.width !== width) highlightCanvas.width = width;
        if (highlightCanvas.height !== height) highlightCanvas.height = height;

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
        const shadowContext = shadowCanvas.getContext('2d');
        const highlightContext = highlightCanvas.getContext('2d');
        const shadowData = shadowContext.createImageData(width, height);
        const highlightData = highlightContext.createImageData(width, height);
        for (let index = 0; index < pixels.length; index += 4) {
            const red = crackLevels[pixels[index]];
            const green = crackLevels[pixels[index + 1]];
            const blue = crackLevels[pixels[index + 2]];
            const luminance = (red + green + blue) / 3;
            const crackAlpha = Math.max(0, Math.min(255, (255 - luminance - 6) * 1.2));
            shadowData.data[index + 3] = crackAlpha;
            highlightData.data[index] = 255;
            highlightData.data[index + 1] = 255;
            highlightData.data[index + 2] = 255;
            highlightData.data[index + 3] = crackAlpha;
            const crackValue = damageColor === 'white' ? 255 : 0;
            pixels[index] = crackValue;
            pixels[index + 1] = crackValue;
            pixels[index + 2] = crackValue;
            pixels[index + 3] = crackAlpha;
        }
        shadowContext.putImageData(shadowData, 0, 0);
        highlightContext.putImageData(highlightData, 0, 0);
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

    async function composeFire(canvas, level, seed, imagesByLevel, token, width, height) {
        const profile = level === 2 ? 'medium' : 'light';
        const candidates = Array.isArray(imagesByLevel?.[profile])
            ? imagesByLevel[profile].filter(function (path) { return typeof path === 'string' && path.length > 0; })
            : [];
        const imagesKey = JSON.stringify(candidates);

        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;
        const context = canvas.getContext('2d');
        context.clearRect(0, 0, width, height);
        fireInputMask = null;

        if (candidates.length === 0) {
            canvas.dataset.fireLevel = String(level);
            canvas.dataset.fireSeed = String(seed);
            canvas.dataset.fireImages = imagesKey;
            canvas.dataset.width = String(width);
            canvas.dataset.height = String(height);
            return;
        }

        const path = candidates[Math.floor(random(seed + level * phaseSeedStep) * candidates.length)];
        const image = await loadAssetImage(path);
        if (token !== renderToken || !canvas.isConnected) return;

        context.globalCompositeOperation = 'source-over';
        context.fillStyle = '#fff';
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = 'multiply';
        context.drawImage(image, 0, 0, width, height);

        // Fire assets may have an opaque white background. Convert white to
        // transparency while preserving coloured scorch and heat pixels.
        const imageData = context.getImageData(0, 0, width, height);
        const pixels = imageData.data;
        const inputMaskPixels = new Uint8Array(width * height);
        const inputThreshold = Math.max(0, Math.min(1,
            Number(lastData.fireInputBlockThreshold) || 0));
        for (let index = 0; index < pixels.length; index += 4) {
            const distanceFromWhite = 255 - Math.min(pixels[index], pixels[index + 1], pixels[index + 2]);
            const fireAlpha = Math.max(0, Math.min(255, (distanceFromWhite - 5) * 1.25));
            const luminance = (pixels[index] * 0.2126) + (pixels[index + 1] * 0.7152)
                + (pixels[index + 2] * 0.0722);
            pixels[index + 3] = fireAlpha;
            inputMaskPixels[index / 4] = fireAlpha > 32 && (1 - luminance / 255) >= inputThreshold ? 1 : 0;
        }
        context.putImageData(imageData, 0, 0);
        if (token !== renderToken || !canvas.isConnected) return;
        fireInputMask = { pixels: inputMaskPixels, width, height };
        context.globalCompositeOperation = 'source-over';
        canvas.dataset.fireLevel = String(level);
        canvas.dataset.fireSeed = String(seed);
        canvas.dataset.fireImages = imagesKey;
        canvas.dataset.width = String(width);
        canvas.dataset.height = String(height);
    }

    function render() {
        const overlay = ensureOverlay(currentPhoneContainer);
        if (!overlay) return;
        const canvas = overlay.querySelector('#lb-brokenphone-canvas');
        const shadowCanvas = overlay.querySelector('#lb-brokenphone-crack-shadow');
        const highlightCanvas = overlay.querySelector('#lb-brokenphone-crack-highlight');
        const fireCanvas = overlay.querySelector('#lb-brokenphone-fire');
        const hackScreen = overlay.querySelector('#lb-brokenphone-hack');
        const hackImage = hackScreen?.querySelector('#lb-brokenphone-hack-image');
        const level = Math.max(0, Math.min(3, Number(lastData.damageLevel) || 0));
        const fireLevel = Math.max(0, Math.min(2, Number(lastData.fireLevel) || 0));
        const hacked = lastData.isHacked === true;
        const phoneVisible = lastData.state !== 'closed';
        if (hackImage) {
            const imageUrl = assetUrl(lastData.hackImage, 'hack/ahahah.gif');
            if (hackImage.src !== imageUrl) hackImage.src = imageUrl;
        }
        syncHackPhase(phoneVisible);
        const hackVisualActive = hackPhase !== 'idle';
        overlay.style.pointerEvents = touchFaultActive || hackVisualActive ? 'auto' : 'none';
        const seed = Number(lastData.damageSeed) || 1;
        const fireSeed = Number(lastData.fireSeed) || 1;
        const fireImages = lastData.fireImages || { light: [], medium: [] };
        const damageColor = lastData.damageColor === 'white' ? 'white' : 'black';
        const visible = (level > 0 || fireLevel > 0 || hacked || hackVisualActive) && phoneVisible;
        overlay.style.filter = 'none';
        overlay.style.mixBlendMode = 'normal';
        overlay.style.backgroundColor = 'transparent';
        canvas.style.mixBlendMode = damageColor === 'white' ? 'screen' : 'multiply';
        
        renderToken += 1;
        if (!visible) {
            fireInputMask = null;
            overlay.style.display = 'none';
            canvas.style.display = 'none';
            shadowCanvas.style.display = 'none';
            highlightCanvas.style.display = 'none';
            fireCanvas.style.display = 'none';
            if (hackScreen) hackScreen.style.display = 'none';
            stopHackSound();
            const context = canvas.getContext('2d');
            context.clearRect(0, 0, canvas.width, canvas.height);
            shadowCanvas.getContext('2d').clearRect(0, 0, shadowCanvas.width, shadowCanvas.height);
            highlightCanvas.getContext('2d').clearRect(0, 0, highlightCanvas.width, highlightCanvas.height);
            fireCanvas.getContext('2d').clearRect(0, 0, fireCanvas.width, fireCanvas.height);
            canvas.dataset.phases = '0';
            canvas.dataset.damageLevel = '0';
            canvas.dataset.damageSeed = '0';
            canvas.dataset.damageColor = String(damageColor);
            canvas.dataset.width = '0';
            canvas.dataset.height = '0';
            canvas.dataset.transforms = '[]';
            return;
        }

        if (hackScreen) hackScreen.style.display = hackVisualActive ? 'flex' : 'none';

        const pixelRatio = Math.min(Number(targetWindow && targetWindow.devicePixelRatio) || 1, 2);
        const displayWidth = overlay.parentElement.clientWidth || overlay.clientWidth || 290;
        const displayHeight = overlay.parentElement.clientHeight || overlay.clientHeight || 585;
        const width = Math.max(1, Math.round(displayWidth * pixelRatio));
        const height = Math.max(1, Math.round(displayHeight * pixelRatio));
        const token = renderToken;

        if (level === 0) {
            canvas.style.display = 'none';
            shadowCanvas.style.display = 'none';
            highlightCanvas.style.display = 'none';
        } else {
            canvas.style.display = 'block';
            shadowCanvas.style.display = 'block';
            highlightCanvas.style.display = 'block';
            const crackMatches = Number(canvas.dataset.damageLevel) === level
                && Number(canvas.dataset.damageSeed) === seed
                && canvas.dataset.damageColor === damageColor
                && Number(canvas.dataset.width) === width
                && Number(canvas.dataset.height) === height;
            if (!crackMatches) {
                composeDamage(canvas, level, seed, damageColor, token, width, height).catch(reportLoadError);
            }
        }

        if (fireLevel === 0) {
            fireInputMask = null;
            fireCanvas.style.display = 'none';
        } else {
            fireCanvas.style.display = 'block';
            const profile = fireLevel === 2 ? 'medium' : 'light';
            const configuredImages = Array.isArray(fireImages[profile]) ? fireImages[profile] : [];
            const fireMatches = Number(fireCanvas.dataset.fireLevel) === fireLevel
                && Number(fireCanvas.dataset.fireSeed) === fireSeed
                && fireCanvas.dataset.fireImages === JSON.stringify(configuredImages)
                && Number(fireCanvas.dataset.width) === width
                && Number(fireCanvas.dataset.height) === height
                && fireInputMask !== null;
            if (!fireMatches) {
                composeFire(fireCanvas, fireLevel, fireSeed, fireImages, token, width, height).catch(reportLoadError);
            }
        }
        overlay.style.display = 'block';
    }

    function reportLoadError(error) {
        const message = error instanceof Error ? error.message : String(error);
        if (reportedLoadErrors.has(message)) return;
        reportedLoadErrors.add(message);
        console.warn('[lb-brokenphone]', message);
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
        ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'dblclick',
            'touchstart', 'touchend', 'contextmenu', 'wheel'].forEach(function (type) {
            targetWindow.addEventListener(type, blockDamagedInput, { capture: true, passive: false });
        });
        phoneHostObserver = new MutationObserver(schedulePhoneContainerCheck);
        phoneHostObserver.observe(targetDocument.documentElement, { childList: true, subtree: true });
        checkPhoneContainer();
    }

    function scheduleConnectionCheck() {
        if (connectTimer !== null) window.clearTimeout(connectTimer);
        connectTimer = window.setTimeout(function () {
            connectTimer = null;
            connectRenderer();
            scheduleConnectionCheck();
        }, observedDocument ? 5000 : 1000);
    }

    function disconnectObservedDocument() {
        if (observedWindow) {
            ['keydown', 'keyup', 'keypress'].forEach(function (type) {
                observedWindow.removeEventListener(type, blockHackKeyboard, true);
            });
            ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'dblclick',
                'touchstart', 'touchend', 'contextmenu', 'wheel'].forEach(function (type) {
                observedWindow.removeEventListener(type, blockDamagedInput, true);
            });
        }
        if (phoneHostObserver) phoneHostObserver.disconnect();
        phoneHostObserver = null;
        if (phoneCheckFrame !== null) window.cancelAnimationFrame(phoneCheckFrame);
        phoneCheckFrame = null;
        detachFromCurrentContainer();
        observedWindow = null;
        observedDocument = null;
    }

    function cleanup() {
        renderToken += 1;
        if (renderFrame !== null) window.cancelAnimationFrame(renderFrame);
        renderFrame = null;
        if (connectTimer !== null) window.clearTimeout(connectTimer);
        connectTimer = null;
        stopHackImmediately();
        hackAudio = null;
        hackAudioPath = null;
        disconnectObservedDocument();
        removeOverlay();
        targetDocument = null;
        targetWindow = null;
    }

    connectRenderer();
    scheduleConnectionCheck();
    window.addEventListener('pagehide', cleanup);
    window.addEventListener('beforeunload', cleanup);
})();
