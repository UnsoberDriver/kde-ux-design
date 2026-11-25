(function () {
    var w = workspace.activeWindow;
    var isDesktop = !w || w.desktopWindow === true;
    if (isDesktop) {
        // Extinction directe via la session KDE (pas de menu a focus fragile).
        callDBus("org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndShutdown");
    } else {
        w.closeWindow();
    }
})();
