/* =========================================================
   RunetToday — Main JavaScript
   ========================================================= */

"use strict";


/* ---------------------------------------------------------
   DOM helpers
   --------------------------------------------------------- */

const $ = (selector, parent = document) => {
    return parent.querySelector(selector);
};


const $$ = (selector, parent = document) => {
    return Array.from(parent.querySelectorAll(selector));
};


/* ---------------------------------------------------------
   DOM ready
   --------------------------------------------------------- */

document.addEventListener("DOMContentLoaded", () => {

    initNavigation();
    initSmoothScroll();
    initCopyButtons();
    initCurrentYear();
    initHeaderState();
    initExternalLinks();

});


/* ---------------------------------------------------------
   Navigation
   --------------------------------------------------------- */

function initNavigation() {

    const header = $(".site-header");

    if (!header) {
        return;
    }


    const nav = $(".site-nav", header);

    if (!nav) {
        return;
    }


    /*
     * Mobile navigation button.
     *
     * If the button does not exist yet in the HTML,
     * the script creates it automatically.
     */

    let menuButton = $(".mobile-menu-button", header);

    if (!menuButton) {

        menuButton = document.createElement("button");

        menuButton.type = "button";

        menuButton.className = "mobile-menu-button";

        menuButton.setAttribute(
            "aria-label",
            "Open navigation"
        );

        menuButton.setAttribute(
            "aria-expanded",
            "false"
        );

        menuButton.innerHTML = `
            <span></span>
            <span></span>
            <span></span>
        `;

        header.appendChild(menuButton);
    }


    menuButton.addEventListener("click", () => {

        const isOpen =
            header.classList.toggle("menu-open");

        menuButton.setAttribute(
            "aria-expanded",
            String(isOpen)
        );

        menuButton.setAttribute(
            "aria-label",
            isOpen
                ? "Close navigation"
                : "Open navigation"
        );

    });


    $$(".site-nav a", header).forEach((link) => {

        link.addEventListener("click", () => {

            header.classList.remove("menu-open");

            menuButton.setAttribute(
                "aria-expanded",
                "false"
            );

            menuButton.setAttribute(
                "aria-label",
                "Open navigation"
            );

        });

    });


    document.addEventListener("click", (event) => {

        if (!header.contains(event.target)) {

            header.classList.remove("menu-open");

            menuButton.setAttribute(
                "aria-expanded",
                "false"
            );

        }

    });

}


/* ---------------------------------------------------------
   Smooth scrolling
   --------------------------------------------------------- */

function initSmoothScroll() {

    $$('a[href^="#"]').forEach((link) => {

        link.addEventListener("click", (event) => {

            const targetId =
                link.getAttribute("href");

            if (
                !targetId ||
                targetId === "#"
            ) {
                return;
            }


            const target =
                document.querySelector(targetId);

            if (!target) {
                return;
            }


            event.preventDefault();


            const header =
                $(".site-header");

            const headerHeight =
                header
                    ? header.offsetHeight
                    : 0;


            const targetPosition =
                target.getBoundingClientRect().top +
                window.scrollY -
                headerHeight -
                24;


            window.scrollTo({
                top: targetPosition,
                behavior: "smooth"
            });

        });

    });

}


/* ---------------------------------------------------------
   Copy buttons
   --------------------------------------------------------- */

function initCopyButtons() {

    const commands = $$(
        "[data-copy]"
    );


    commands.forEach((element) => {

        element.addEventListener(
            "click",
            async () => {

                const value =
                    element.dataset.copy;

                if (!value) {
                    return;
                }


                const originalText =
                    element.textContent;


                try {

                    await navigator.clipboard.writeText(
                        value
                    );

                    element.textContent =
                        "Copied";


                    element.classList.add(
                        "copied"
                    );


                    window.setTimeout(() => {

                        element.textContent =
                            originalText;

                        element.classList.remove(
                            "copied"
                        );

                    }, 1600);

                } catch (error) {

                    console.warn(
                        "Unable to copy text:",
                        error
                    );

                }

            }
        );

    });

}


/* ---------------------------------------------------------
   Current year
   --------------------------------------------------------- */

function initCurrentYear() {

    const yearElements =
        $$("[data-current-year]");


    const year =
        new Date().getFullYear();


    yearElements.forEach((element) => {

        element.textContent =
            year;

    });

}


/* ---------------------------------------------------------
   Header state
   --------------------------------------------------------- */

function initHeaderState() {

    const header =
        $(".site-header");

    if (!header) {
        return;
    }


    const updateHeader =
        () => {

            if (window.scrollY > 24) {

                header.classList.add(
                    "is-scrolled"
                );

            } else {

                header.classList.remove(
                    "is-scrolled"
                );

            }

        };


    updateHeader();


    window.addEventListener(
        "scroll",
        updateHeader,
        {
            passive: true
        }
    );

}


/* ---------------------------------------------------------
   External links
   --------------------------------------------------------- */

function initExternalLinks() {

    $$(
        'a[href^="http://"], a[href^="https://"]'
    ).forEach((link) => {

        const currentHost =
            window.location.hostname;

        let targetHost = "";

        try {

            targetHost =
                new URL(link.href).hostname;

        } catch {
            return;
        }


        if (
            targetHost &&
            targetHost !== currentHost
        ) {

            link.setAttribute(
                "target",
                "_blank"
            );

            link.setAttribute(
                "rel",
                "noopener noreferrer"
            );

        }

    });

}