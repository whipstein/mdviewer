// MDViewer JS Bridge
// Handles Markdown rendering and Swift <-> JS communication.

(function () {
    'use strict';

    // -- Shiki highlighter (resolved async on page load)
    let shikiHighlighter = null;

    if (window.__shikiReady) {
        window.__shikiReady.then(function (h) { shikiHighlighter = h; });
    }

    // -- Mermaid init (must run before DOMContentLoaded diagrams)
    if (typeof mermaid !== 'undefined') {
        mermaid.initialize({
            startOnLoad: false,
            theme: 'default',
            securityLevel: 'loose'
        });
    }

    let currentDocumentKey = null;

    function collapsedStorageKey() {
        return currentDocumentKey ? ('mdv-collapsed:' + currentDocumentKey) : null;
    }

    function loadCollapsedSet() {
        const key = collapsedStorageKey();
        if (!key) return new Set();
        try {
            const raw = localStorage.getItem(key);
            return raw ? new Set(JSON.parse(raw)) : new Set();
        } catch (e) {
            return new Set();
        }
    }

    function saveCollapsedSet(set) {
        const key = collapsedStorageKey();
        if (!key) return;
        try {
            localStorage.setItem(key, JSON.stringify(Array.from(set)));
        } catch (e) { /* ignore */ }
    }
    
    function slugify(text) {
        return text
            .toLowerCase()
            .replace(/[^\w\s-]/g, '')
            .replace(/\s+/g, '-')
            .replace(/-+/g, '-')
            .trim();
    }

    function escapeHtml(str) {
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function highlightCode(code, lang) {
        const fallback = function () {
            const label = lang ? `<span class="code-lang-label">${escapeHtml(lang)}</span>` : '';
            return `<div class="code-block-wrapper">${label}<pre><code>${escapeHtml(code)}</code></pre></div>`;
        };

        if (!shikiHighlighter) { return fallback(); }

        try {
            const loaded = shikiHighlighter.getLoadedLanguages();
            const resolvedLang = loaded.includes(lang) ? lang : 'text';

            const html = shikiHighlighter.codeToHtml(code, {
                lang: resolvedLang,
                themes: { light: 'github-light', dark: 'github-dark' }
            });

            if (lang) {
                return html
                    .replace('<pre ', `<div class="code-block-wrapper"><span class="code-lang-label">${escapeHtml(lang)}</span><pre `)
                    .replace('</pre>', '</pre></div>');
            }
            return html;
        } catch (_) {
            return fallback();
        }
    }

    // Base directory for resolving relative image paths, served via the
    // mdviewer-local:// custom scheme. Set by Swift through setBaseURL().
    let localBaseURL = null;

    function wrapCollapsibleSections(root) {
        const HEADING_TAGS = ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'];
        const nodes = Array.from(root.childNodes);
        root.innerHTML = '';

        const collapsedSet = loadCollapsedSet();
        const stack = [{ level: 0, container: root }];

        nodes.forEach(function (node) {
            if (node.nodeType === 3 && !node.textContent.trim()) { return; }

            const tag = node.nodeType === 1 ? node.tagName : null;

            if (tag && HEADING_TAGS.indexOf(tag) !== -1) {
                const level = parseInt(tag.substring(1), 10);

                while (stack.length > 1 && stack[stack.length - 1].level >= level) {
                    stack.pop();
                }

                const anchorId = node.id || null;
                const section = document.createElement('section');
                section.className = 'collapsible-section';

                const header = document.createElement('div');
                header.className = 'collapsible-header';
                header.setAttribute('role', 'button');
                header.setAttribute('tabindex', '0');

                const toggle = document.createElement('button');
                toggle.type = 'button';
                toggle.className = 'collapsible-toggle';
                toggle.tabIndex = -1;
                toggle.appendChild(createChevronSVG());

                const startCollapsed = anchorId && collapsedSet.has(anchorId);
                toggle.setAttribute('aria-expanded', startCollapsed ? 'false' : 'true');
                toggle.setAttribute('aria-label', startCollapsed ? 'Expand section' : 'Collapse section');
                if (startCollapsed) { section.classList.add('collapsed'); }

                header.appendChild(toggle);
                header.appendChild(node);
                section.appendChild(header);

                const body = document.createElement('div');
                body.className = 'collapsible-body';
                section.appendChild(body);

                header.addEventListener('click', function (e) {
                    if (e.target.closest('a')) { return; }
                    const collapsed = section.classList.toggle('collapsed');
                    toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
                    toggle.setAttribute('aria-label', collapsed ? 'Expand section' : 'Collapse section');

                    if (anchorId) {
                        const set = loadCollapsedSet();
                        if (collapsed) { set.add(anchorId); } else { set.delete(anchorId); }
                        saveCollapsedSet(set);
                    }
                });
                header.addEventListener('keydown', function (e) {
                    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); header.click(); }
                });

                stack[stack.length - 1].container.appendChild(section);
                stack.push({ level: level, container: body });
            } else {
                stack[stack.length - 1].container.appendChild(node);
            }
        });
    }

    function setAllSections(collapsed) {
        const sections = document.querySelectorAll('.collapsible-section');
        const set = new Set();
        sections.forEach(function (section) {
            const toggle = section.querySelector(':scope > .collapsible-header > .collapsible-toggle');
            const heading = section.querySelector(':scope > .collapsible-header > h1, :scope > .collapsible-header > h2, :scope > .collapsible-header > h3, :scope > .collapsible-header > h4, :scope > .collapsible-header > h5, :scope > .collapsible-header > h6');
            const anchorId = heading ? heading.id : null;

            section.classList.toggle('collapsed', collapsed);
            if (toggle) {
                toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
                toggle.setAttribute('aria-label', collapsed ? 'Expand section' : 'Collapse section');
            }
            if (anchorId && collapsed) { set.add(anchorId); }
        });
        saveCollapsedSet(set);
    }
    
    function createChevronSVG() {
        const svgNS = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(svgNS, 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('width', '14');
        svg.setAttribute('height', '14');
        svg.classList.add('collapsible-chevron');

        const path = document.createElementNS(svgNS, 'path');
        path.setAttribute('d', 'M6 9l6 6 6-6');
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', 'currentColor');
        path.setAttribute('stroke-width', '2');
        path.setAttribute('stroke-linecap', 'round');
        path.setAttribute('stroke-linejoin', 'round');
        svg.appendChild(path);

        return svg;
    }

    function addCopyButtons(root) {
        const COPY_SVG = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
        const CHECK_SVG = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';

        const blocks = root.querySelectorAll('.code-block-wrapper, pre');
        blocks.forEach(function (block) {
            if (block.tagName === 'PRE' && block.closest('.code-block-wrapper')) { return; }
            if (block.querySelector(':scope > .code-copy-btn')) { return; }

            const codeEl = block.querySelector('code') || block.querySelector('pre');
            if (!codeEl) { return; }

            block.style.position = block.style.position || 'relative';

            const btn = document.createElement('button');
            btn.className = 'code-copy-btn';
            btn.type = 'button';
            btn.setAttribute('aria-label', 'Copy code');
            btn.innerHTML = COPY_SVG;

            btn.addEventListener('click', function (e) {
                e.stopPropagation();
                const text = codeEl.innerText;
                navigator.clipboard.writeText(text).then(function () {
                    btn.innerHTML = CHECK_SVG;
                    btn.classList.add('copied');
                    setTimeout(function () {
                        btn.innerHTML = COPY_SVG;
                        btn.classList.remove('copied');
                    }, 1500);
                }).catch(function () {
                    btn.setAttribute('aria-label', 'Copy failed');
                    setTimeout(function () { btn.setAttribute('aria-label', 'Copy code'); }, 1500);
                });
            });

            block.appendChild(btn);
        });
    }
    
    // Rewrite relative image sources (and other local resources) to the
    // mdviewer-local:// scheme so the Swift scheme handler can serve them.
    // Absolute URLs (http, https, data, file, the scheme itself) are left alone.
    function rewriteLocalResources(root) {
        if (!localBaseURL) { return; }

        const isAbsolute = function (src) {
            return /^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith('//') || src.startsWith('#');
        };

        root.querySelectorAll('img[src]').forEach(function (img) {
            const src = img.getAttribute('src');
            if (!src || isAbsolute(src)) { return; }
            // Encode each path segment but preserve slashes.
            const encoded = src.split('/').map(encodeURIComponent).join('/');
            const path = encoded.startsWith('/') ? encoded.slice(1) : encoded;
            img.setAttribute('src', localBaseURL + path);
        });
    }

    // Find the anchor id of the collapsible section containing a given element
    function sectionAnchorFromElement(el) {
        let node = el;
        while (node && node !== document.body) {
            if (node.classList && node.classList.contains('collapsible-section')) {
                const heading = node.querySelector(':scope > .collapsible-header > h1, :scope > .collapsible-header > h2, :scope > .collapsible-header > h3, :scope > .collapsible-header > h4, :scope > .collapsible-header > h5, :scope > .collapsible-header > h6');
                return heading ? heading.id : null;
            }
            node = node.parentElement;
        }
        return null;
    }

    function sectionFromAnchor(anchor) {
        const heading = document.getElementById(anchor);
        if (!heading) return null;
        return heading.closest('.collapsible-section');
    }

    function setSectionSubtree(section, collapsed) {
        if (!section) return;
        const set = loadCollapsedSet();
        const apply = function (sec) {
            const heading = sec.querySelector(':scope > .collapsible-header > h1, :scope > .collapsible-header > h2, :scope > .collapsible-header > h3, :scope > .collapsible-header > h4, :scope > .collapsible-header > h5, :scope > .collapsible-header > h6');
            const toggle = sec.querySelector(':scope > .collapsible-header > .collapsible-toggle');
            sec.classList.toggle('collapsed', collapsed);
            if (toggle) {
                toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
                toggle.setAttribute('aria-label', collapsed ? 'Expand section' : 'Collapse section');
            }
            if (heading && heading.id) {
                if (collapsed) { set.add(heading.id); } else { set.delete(heading.id); }
            }
            // recurse into nested collapsible sections inside this one's body
            const body = sec.querySelector(':scope > .collapsible-body');
            if (body) {
                body.querySelectorAll(':scope > .collapsible-section').forEach(apply);
            }
        };
        apply(section);
        saveCollapsedSet(set);
    }

    // -- In-page search -----------------------------------------------------
    // Custom search (instead of WKWebView.find) so we can highlight every match
    // across the whole document — including inside collapsed sections — report a
    // match count/index, and expand collapsed sections when navigating into them.
    let searchState = { query: '', matches: [], current: -1 };

    function reportSearchResult() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.searchResult) {
            window.webkit.messageHandlers.searchResult.postMessage({
                count: searchState.matches.length,
                current: searchState.matches.length ? searchState.current + 1 : 0
            });
        }
    }

    function clearSearchHighlights() {
        const content = document.getElementById('content');
        if (content) {
            const marks = content.querySelectorAll('mark.mdviewer-search-hit');
            marks.forEach(function (mark) {
                const parent = mark.parentNode;
                if (!parent) return;
                parent.replaceChild(document.createTextNode(mark.textContent), mark);
                parent.normalize();
            });
        }
        searchState = { query: '', matches: [], current: -1 };
    }

    function expandCollapsedAncestors(el) {
        let node = el.parentElement;
        while (node) {
            if (node.classList && node.classList.contains('collapsible-section') && node.classList.contains('collapsed')) {
                node.classList.remove('collapsed');
                const btn = node.querySelector(':scope > .collapsible-header > .collapsible-toggle');
                if (btn) {
                    btn.setAttribute('aria-expanded', 'true');
                    btn.setAttribute('aria-label', 'Collapse section');
                }
            }
            node = node.parentElement;
        }
    }

    function setCurrentMatch(index) {
        const matches = searchState.matches;
        if (!matches.length) { reportSearchResult(); return; }

        if (searchState.current >= 0 && searchState.current < matches.length) {
            matches[searchState.current].classList.remove('current');
        }
        if (index < 0) index = matches.length - 1;
        if (index >= matches.length) index = 0;
        searchState.current = index;

        const mark = matches[index];
        mark.classList.add('current');
        expandCollapsedAncestors(mark);
        mark.scrollIntoView({ behavior: 'smooth', block: 'center' });
        reportSearchResult();
    }

    function runSearch(query) {
        clearSearchHighlights();
        const content = document.getElementById('content');
        if (!query || !content) { reportSearchResult(); return; }

        searchState.query = query;
        const needle = query.toLowerCase();

        const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
                const tag = node.parentNode ? node.parentNode.nodeName : '';
                if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });

        const textNodes = [];
        let node;
        while ((node = walker.nextNode())) textNodes.push(node);

        textNodes.forEach(function (textNode) {
            const text = textNode.nodeValue;
            const lower = text.toLowerCase();
            let idx = lower.indexOf(needle);
            if (idx === -1) return;

            const frag = document.createDocumentFragment();
            let last = 0;
            while (idx !== -1) {
                if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
                const mark = document.createElement('mark');
                mark.className = 'mdviewer-search-hit';
                mark.textContent = text.slice(idx, idx + query.length);
                frag.appendChild(mark);
                searchState.matches.push(mark);
                last = idx + query.length;
                idx = lower.indexOf(needle, last);
            }
            if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
            textNode.parentNode.replaceChild(frag, textNode);
        });

        if (searchState.matches.length) {
            setCurrentMatch(0);
        } else {
            reportSearchResult();
        }
    }

    // -- Public MDViewer API (called from Swift via evaluateJavaScript)
    window.MDViewer = {

        setContent: async function (markdown) {
            try {
                if (!shikiHighlighter && window.__shikiReady) {
                    shikiHighlighter = await Promise.race([
                        window.__shikiReady,
                        new Promise(function (resolve) { setTimeout(function () { resolve(null); }, 8000); })
                    ]);
                }
                
                const headingsRef = [];
                const renderer = new marked.Renderer();
                
                renderer.heading = function (text, level, raw) {
                    const anchor = slugify(typeof raw === 'string' ? raw : text);
                    headingsRef.push({ level: level, title: typeof raw === 'string' ? raw : text, anchor: anchor });
                    return `<h${level} id="${anchor}">${text}</h${level}>\n`;
                };
                
                renderer.code = function (code, lang) {
                    if (lang === 'mermaid') {
                        return `<div class="mermaid">${escapeHtml(code)}</div>`;
                    }
                    return highlightCode(code, lang);
                };
                
                // Pre-process math: protect $...$ from marked parsing
                const mathBlocks = [];
                let processed = markdown;

                // First, hide code from the math regex so shell/code like `echo $FOO`
                // isn't misread as math. Code is restored before marked parses it, so it
                // still renders (and highlights) normally.
                const codeSpans = [];
                processed = processed.replace(/```[\s\S]*?```|~~~[\s\S]*?~~~/g, function (match) {
                    codeSpans.push(match);
                    // Preserve line count so source-line mapping stays aligned.
                    const newlines = (match.match(/\n/g) || []).length;
                    return `CODESPAN_${codeSpans.length - 1}_END` + '\n'.repeat(newlines);
                });
                processed = processed.replace(/`[^`\n]+`/g, function (match) {
                    codeSpans.push(match);
                    return `CODESPAN_${codeSpans.length - 1}_END`;
                });

                processed = processed.replace(/\$\$([^$]+?)\$\$/gs, function (match, expr) {
                    const placeholder = `MATHBLOCK_${mathBlocks.length}_END`;
                    mathBlocks.push({ type: 'block', expr: expr.trim() });
                    // Preserve the original line count so source-line mapping stays aligned.
                    const newlines = (match.match(/\n/g) || []).length;
                    return placeholder + '\n'.repeat(newlines);
                });

                processed = processed.replace(/\$([^$\n]+?)\$/g, function (_, expr) {
                    const placeholder = `MATHINLINE_${mathBlocks.length}_END`;
                    mathBlocks.push({ type: 'inline', expr: expr.trim() });
                    return placeholder;
                });

                // Restore code now that math substitution is done.
                processed = processed.replace(/CODESPAN_(\d+)_END/g, function (_, i) {
                    return codeSpans[parseInt(i, 10)];
                });
                
                let html = marked.parse(processed, { renderer: renderer });

                // Record the source line where each top-level block begins so a click
                // in the preview can locate the matching line in the editor.
                const blockLineStarts = [];
                let lineCursor = 0;
                marked.lexer(processed).forEach(function (token) {
                    const start = lineCursor;
                    lineCursor += ((token.raw || '').match(/\n/g) || []).length;
                    if (token.type !== 'space') blockLineStarts.push(start);
                });

                // Restore math
                if (typeof katex !== 'undefined') {
                    mathBlocks.forEach(function (m, i) {
                        const blockPh = new RegExp(`MATHBLOCK_${i}_END`, 'g');
                        const inlinePh = new RegExp(`MATHINLINE_${i}_END`, 'g');
                        try {
                            const rendered = katex.renderToString(m.expr, {
                                displayMode: m.type === 'block',
                                throwOnError: false
                            });
                            html = html.replace(blockPh, rendered).replace(inlinePh, rendered);
                        } catch (e) {
                            html = html.replace(blockPh, escapeHtml(m.expr))
                            .replace(inlinePh, escapeHtml(m.expr));
                        }
                    });
                }
                
                const contentEl = document.getElementById('content');
                contentEl.innerHTML = html;

                // Tag each top-level block with its source line for click-to-locate.
                const topChildren = contentEl.children;
                for (let i = 0; i < topChildren.length && i < blockLineStarts.length; i++) {
                    topChildren[i].setAttribute('data-source-line', blockLineStarts[i]);
                }

                // Resolve relative image paths against the Markdown file's directory
                rewriteLocalResources(contentEl);
                wrapCollapsibleSections(contentEl);
                addCopyButtons(contentEl);
                
                // Render Mermaid diagrams
                if (typeof mermaid !== 'undefined') {
                    try {
                        mermaid.run({ querySelector: '.mermaid' });
                    } catch (e) {
                        console.warn('Mermaid render error:', e);
                    }
                }
                
                // Notify Swift with heading list
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.headingsExtracted) {
                    window.webkit.messageHandlers.headingsExtracted.postMessage(headingsRef);
                }
                
                // Notify Swift render complete
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                    window.webkit.messageHandlers.renderComplete.postMessage(null);
                }
            } catch (err) {
                console.error('MDViewer render failure:', err, err && err.stack);
            }
        },

        setDocumentPath: function (path) {
            currentDocumentKey = path;
        },

        collapseAll: function () { setAllSections(true); },
        expandAll: function () { setAllSections(false); },
        
        setTheme: function (themeName) {
            const link = document.getElementById('theme-css');
            if (link) {
                link.href = `themes/${themeName}.css`;
            }
            // Toggle Shiki dark-theme class
            const isDark = themeName.includes('dark');
            document.body.classList.toggle('dark-theme', isDark);

            // Update mermaid theme
            if (typeof mermaid !== 'undefined') {
                mermaid.initialize({
                    startOnLoad: false,
                    theme: isDark ? 'dark' : 'default',
                    securityLevel: 'loose'
                });
            }
        },

        setFontSize: function (size) {
            document.documentElement.style.setProperty('--font-size', size + 'px');
        },

        scrollToAnchor: function (anchorId) {
            const el = document.getElementById(anchorId);
            if (el) {
                let node = el.parentElement;
                while (node) {
                    if (node.classList && node.classList.contains('collapsible-section') && node.classList.contains('collapsed')) {
                        node.classList.remove('collapsed');
                        const btn = node.querySelector(':scope > .collapsible-header > .collapsible-toggle');
                        if (btn) {
                            btn.setAttribute('aria-expanded', 'true');
                            btn.setAttribute('aria-label', 'Collapse section');
                        }
                    }
                    node = node.parentElement;
                }
                el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                el.classList.add('heading-anchor-target');
                setTimeout(function () {
                    el.classList.remove('heading-anchor-target');
                }, 2000);
            }
        },
        
        findText: function (text) {
            if (window.find) {
                window.find(text, false, false, true, false, true, false);
            }
        },

        // In-page search API used by the search bar.
        search: function (query) { runSearch(query); },
        searchNext: function () { setCurrentMatch(searchState.current + 1); },
        searchPrev: function () { setCurrentMatch(searchState.current - 1); },
        clearSearch: function () { clearSearchHighlights(); reportSearchResult(); },

        collapseSection: function (anchor) { setSectionSubtree(sectionFromAnchor(anchor), true); },
        expandSection: function (anchor) { setSectionSubtree(sectionFromAnchor(anchor), false); },

        // Store the anchor under the last right-click, for the native menu to read
        _lastContextAnchor: null,
        
        setBaseURL: function (url) {
            // Store the base for relative image resolution. We do NOT set a
            // <base> element, since that would also redirect the renderer's own
            // relative resources (theme CSS, vendor scripts) and break them.
            localBaseURL = url;

            // Re-resolve any images already in the DOM (base may arrive after content).
            const contentEl = document.getElementById('content');
            if (contentEl) {
                rewriteLocalResources(contentEl);
            }
        }
    };

    // Track scroll position and notify Swift
    let scrollTimer = null;
    window.addEventListener('scroll', function () {
        if (scrollTimer) clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function () {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollPositionChanged) {
                window.webkit.messageHandlers.scrollPositionChanged.postMessage({
                    y: window.scrollY,
                    height: document.body.scrollHeight
                });
            }
        }, 100);
    });

    // Click-to-locate: clicking rendered content moves the editor to the source line.
    document.addEventListener('click', function (e) {
        // Links and in-content buttons (e.g. copy) have their own behavior.
        if (e.target.closest('a[href]') || e.target.closest('button')) return;
        const block = e.target.closest('[data-source-line]');
        if (!block) return;
        const line = parseInt(block.getAttribute('data-source-line'), 10);
        if (isNaN(line)) return;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorScrollToLine) {
            window.webkit.messageHandlers.editorScrollToLine.postMessage(line);
        }
    });

    // Link hover: notify Swift to display URL in status bar
    document.addEventListener('mouseover', function (e) {
        const link = e.target.closest('a[href]');
        if (link && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHovered) {
            window.webkit.messageHandlers.linkHovered.postMessage(link.href || '');
        }
    });
    document.addEventListener('mouseout', function (e) {
        const link = e.target.closest('a[href]');
        if (link && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHovered) {
            window.webkit.messageHandlers.linkHovered.postMessage('');
        }
    });

    document.addEventListener('click', function (e) {
        const link = e.target.closest('a[href]');
        if (!link) return;

        const rawHref = link.getAttribute('href');
        if (!rawHref) return;

        // In-document anchor
        if (rawHref.startsWith('#')) {
            e.preventDefault();
            window.MDViewer.scrollToAnchor(decodeURIComponent(rawHref.slice(1)));
            return;
        }

        e.preventDefault();

        // Absolute external URL (http, https, mailto, etc.) — pass as-is
        if (/^[a-z][a-z0-9+.-]*:/i.test(rawHref)) {
            window.webkit.messageHandlers.linkClicked.postMessage(rawHref);
            return;
        }

        // Relative link — resolve against the MARKDOWN file's directory, not the renderer.
        // Post the raw relative path; Swift resolves it against the document dir.
        window.webkit.messageHandlers.linkClicked.postMessage('mdviewer-relative:' + rawHref);
    });

    document.addEventListener('contextmenu', function (e) {
        window.MDViewer._lastContextAnchor = sectionAnchorFromElement(e.target);
    });
    
})();
