"use strict";


/* =========================================================
   RunetToday — Animations
   ========================================================= */


/* ---------------------------------------------------------
   Reduced motion
   --------------------------------------------------------- */

const prefersReducedMotion =
    window.matchMedia(
        "(prefers-reduced-motion: reduce)"
    ).matches;


/* ---------------------------------------------------------
   DOM ready
   --------------------------------------------------------- */

document.addEventListener("DOMContentLoaded", () => {

    if (prefersReducedMotion) {
        return;
    }

    initRevealAnimations();
    initHeroAnimations();
    initDashboardAnimations();

});


/* ---------------------------------------------------------
   Reveal animations
   --------------------------------------------------------- */

function initRevealAnimations() {

    const elements = document.querySelectorAll(
        ".section-heading, " +
        ".feature-card, " +
        ".cli-terminal, " +
        ".cta-card, " +
        ".footer"
    );


    if (!elements.length) {
        return;
    }


    elements.forEach((element, index) => {

        element.classList.add(
            "reveal"
        );


        /*
         * Slight stagger between elements
         * in the same section.
         */

        const delay =
            Math.min(index * 50, 300);

        element.style.setProperty(
            "--reveal-delay",
            `${delay}ms`
        );

    });


    const observer =
        new IntersectionObserver(
            (entries, observerInstance) => {

                entries.forEach((entry) => {

                    if (!entry.isIntersecting) {
                        return;
                    }


                    entry.target.classList.add(
                        "is-visible"
                    );


                    observerInstance.unobserve(
                        entry.target
                    );

                });

            },
            {
                threshold: 0.12,
                rootMargin: "0px 0px -40px 0px"
            }
        );


    elements.forEach((element) => {

        observer.observe(element);

    });

}


/* ---------------------------------------------------------
   Hero animation
   --------------------------------------------------------- */

function initHeroAnimations() {

    const hero =
        document.querySelector(".hero");

    if (!hero) {
        return;
    }


    const badge =
        hero.querySelector(".hero-badge");

    const title =
        hero.querySelector(".hero-title");

    const description =
        hero.querySelector(".hero-description");

    const actions =
        hero.querySelector(".hero-actions");

    const install =
        hero.querySelector(".install-command");

    const dashboard =
        document.querySelector(".dashboard");


    const elements = [
        badge,
        title,
        description,
        actions,
        install
    ].filter(Boolean);


    elements.forEach((element, index) => {

        element.classList.add(
            "hero-reveal"
        );

        element.style.setProperty(
            "--hero-delay",
            `${index * 90}ms`
        );

    });


    /*
     * Trigger after the initial browser paint.
     */

    requestAnimationFrame(() => {

        requestAnimationFrame(() => {

            elements.forEach((element) => {

                element.classList.add(
                    "is-visible"
                );

            });


            if (dashboard) {

                dashboard.classList.add(
                    "dashboard-intro"
                );

                window.setTimeout(() => {

                    dashboard.classList.add(
                        "is-visible"
                    );

                }, 180);

            }

        });

    });

}


/* ---------------------------------------------------------
   Dashboard animation
   --------------------------------------------------------- */

function initDashboardAnimations() {

    const dashboard =
        document.querySelector(".dashboard");

    if (!dashboard) {
        return;
    }


    const metrics =
        dashboard.querySelectorAll(
            ".metric-card"
        );


    const panels =
        dashboard.querySelectorAll(
            ".system-panel, .traffic-panel"
        );


    metrics.forEach((element, index) => {

        element.classList.add(
            "dashboard-item-reveal"
        );

        element.style.setProperty(
            "--dashboard-delay",
            `${index * 70}ms`
        );

    });


    panels.forEach((element, index) => {

        element.classList.add(
            "dashboard-item-reveal"
        );

        element.style.setProperty(
            "--dashboard-delay",
            `${(index + metrics.length) * 70}ms`
        );

    });


    /*
     * Dashboard items become visible shortly
     * after the dashboard itself appears.
     */

    window.setTimeout(() => {

        [
            ...metrics,
            ...panels
        ].forEach((element) => {

            element.classList.add(
                "is-visible"
            );

        });

    }, 450);

}