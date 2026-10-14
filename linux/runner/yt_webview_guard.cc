#include "yt_webview_guard.h"

#include <cstring>

#include <gtk/gtk.h>

// Must match CreateConfiguration(title:) in yt_web_login.dart (ASCII-only:
// the title is compared byte-wise here).
static constexpr const char* kYtWindowTitle = "LastWave YouTube Sign In";
// Must match CreateConfiguration(title:) in potoken_engine.dart.
static constexpr const char* kBotGuardTitle = "LastWave BotGuard";
// Marker so the delete-event blocker is attached exactly once per window.
static constexpr const char* kArmedKey = "lastwave-yt-guarded";

static FlMethodChannel* g_channel = nullptr;

// X pressed (or any delete-event): hide instead of destroying. Returning
// TRUE stops GTK's default handler, so the WebKit window — and its EGL
// context — stays alive and no destroy signal ever fires.
static gboolean on_yt_delete_event(GtkWidget* widget, GdkEvent* /*event*/,
                                   gpointer /*user_data*/) {
  gtk_widget_hide(widget);
  return TRUE;
}

static GtkWidget* find_window_by_title(const char* title) {
  GList* tops = gtk_window_list_toplevels();
  GtkWidget* found = nullptr;
  for (GList* l = tops; l != nullptr; l = l->next) {
    if (!GTK_IS_WINDOW(l->data)) {
      continue;
    }
    const gchar* t = gtk_window_get_title(GTK_WINDOW(l->data));
    if (t != nullptr && strcmp(t, title) == 0) {
      found = GTK_WIDGET(l->data);
      break;
    }
  }
  g_list_free(tops);
  return found;
}

static GtkWidget* find_yt_window() {
  return find_window_by_title(kYtWindowTitle);
}

static GtkWidget* find_botguard_window() {
  return find_window_by_title(kBotGuardTitle);
}

static void arm_delete_blocker(GtkWidget* window) {
  if (g_object_get_data(G_OBJECT(window), kArmedKey) != nullptr) {
    return;
  }
  g_object_set_data(G_OBJECT(window), kArmedKey, GINT_TO_POINTER(1));
  g_signal_connect(window, "delete-event", G_CALLBACK(on_yt_delete_event),
                   nullptr);
}

// Depth-first search for the plugin's WebKitWebView inside `widget`.
// Matched by GType name so the runner doesn't need to link webkit2gtk:
// the plugin has already registered the type by the time a window
// exists. Subclasses match too (g_type_is_a).
static GtkWidget* find_webkit_view(GtkWidget* widget) {
  if (widget == nullptr) {
    return nullptr;
  }
  const GType webkit_type = g_type_from_name("WebKitWebView");
  if (webkit_type != 0 && g_type_is_a(G_OBJECT_TYPE(widget), webkit_type)) {
    return widget;
  }
  if (!GTK_IS_CONTAINER(widget)) {
    return nullptr;
  }
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  GtkWidget* found = nullptr;
  for (GList* l = children; l != nullptr && found == nullptr; l = l->next) {
    found = find_webkit_view(GTK_WIDGET(l->data));
  }
  g_list_free(children);
  return found;
}

// Replace the sign-in WebView's whole UA through GObject properties
// (WebKitWebView:settings -> WebKitSettings:user-agent). Returns false
// when the window or view can't be found.
static bool set_user_agent(GtkWidget* window, const gchar* user_agent) {
  GtkWidget* view = find_webkit_view(window);
  if (view == nullptr) {
    return false;
  }
  GObject* settings = nullptr;
  g_object_get(G_OBJECT(view), "settings", &settings, nullptr);
  if (settings == nullptr) {
    return false;
  }
  g_object_set(settings, "user-agent", user_agent, nullptr);
  g_object_unref(settings);
  return true;
}

static void handle_method_call(FlMethodChannel* /*channel*/,
                               FlMethodCall* method_call,
                               gpointer /*user_data*/) {
  const gchar* method = fl_method_call_get_name(method_call);
  GtkWidget* window = find_yt_window();
  if (strcmp(method, "hide") == 0) {
    if (window != nullptr) {
      arm_delete_blocker(window);
      gtk_widget_hide(window);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(window != nullptr);
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  if (strcmp(method, "show") == 0) {
    if (window != nullptr) {
      arm_delete_blocker(window);
      gtk_widget_show(window);
      gtk_window_present(GTK_WINDOW(window));
    }
    g_autoptr(FlValue) result = fl_value_new_bool(window != nullptr);
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  // Full UA replacement for the sign-in window (issue #38). Argument:
  // the UA string. Responds false when the window/view is missing or
  // the argument isn't a non-empty string.
  if (strcmp(method, "setUserAgent") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    bool ok = false;
    if (window != nullptr && args != nullptr &&
        fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      const gchar* ua = fl_value_get_string(args);
      if (ua != nullptr && ua[0] != '\0') {
        ok = set_user_agent(window, ua);
      }
    }
    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  // BotGuard poToken window (potoken_engine.dart): same upstream destroy
  // bug as the sign-in window, plus no visibility/move API on Linux, so
  // it must never be destroyed either — hide and reuse for app lifetime.
  // The Dart side never calls close() on Linux; these are the hide path
  // (called right after create, since plugin hide is a no-op) and a
  // show escape hatch for diagnostics.
  if (strcmp(method, "hideBotGuard") == 0) {
    GtkWidget* bg = find_botguard_window();
    if (bg != nullptr) {
      arm_delete_blocker(bg);
      gtk_widget_hide(bg);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(bg != nullptr);
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  if (strcmp(method, "showBotGuard") == 0) {
    GtkWidget* bg = find_botguard_window();
    if (bg != nullptr) {
      arm_delete_blocker(bg);
      gtk_widget_show(bg);
      gtk_window_present(GTK_WINDOW(bg));
    }
    g_autoptr(FlValue) result = fl_value_new_bool(bg != nullptr);
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

void yt_webview_guard_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                  "LastWaveYtWebviewGuard");
  // Owned by the registrar; kept alive for process lifetime.
  g_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "lastwave/yt_webview",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, handle_method_call,
                                            nullptr, nullptr);
}
