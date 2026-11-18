(function () {
    var w = workspace.activeWindow;
    var isDesktop = !w || w.desktopWindow === true;
    if (isDesktop) {
        callDBus("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptAll");
    } else {
        w.closeWindow();
    }
})();
