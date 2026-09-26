export const THEME_STORAGE_KEY = "themePreference";

/** Script run in <head> before paint so the stored theme applies without a flash; light is the default. */
export const THEME_INIT_SCRIPT = `(function(){var t="light";try{if(localStorage.getItem("${THEME_STORAGE_KEY}")==="dark")t="dark"}catch(e){}document.documentElement.classList.add(t)})();`;
