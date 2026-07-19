/// Name of the JavaScript channel / handler the injected bridge posts to.
///
/// Used both by [inspectorWebViewBridgeJs] (as the transport target) and by
/// the host app when wiring up `JavaScriptChannel` / `addJavaScriptHandler`.
const String kWebViewBridgeChannelName = 'FlutterInspectorBridge';

/// JavaScript payload injected into a WebView page to bridge its
/// `console.*`, `window.onerror`, `unhandledrejection`, `fetch` and
/// `XMLHttpRequest` activity back to the host app as a single JSON string per
/// event, via [kWebViewBridgeChannelName].
///
/// This is a data constant, not Dart logic — it runs inside the WebView's own
/// JS engine. See `docs/plans/2026-07-18-webview-inline-debugging-plan.md`
/// §2 for the wire protocol this payload emits.
const String inspectorWebViewBridgeJs = r'''
(function () {
  if (window.__inspectorBridgeInstalled) return;
  window.__inspectorBridgeInstalled = true;

  var MAX_CHARS = 32768;

  function truncate(s) {
    if (typeof s !== 'string' || s.length <= MAX_CHARS) return { v: s, cut: false };
    return { v: s.slice(0, MAX_CHARS) + '…[truncated]', cut: true };
  }

  function safeStringify(o) {
    try {
      return JSON.stringify(o);
    } catch (e) {
      return String(o);
    }
  }

  function headersToObject(h) {
    var obj = {};
    if (!h) return obj;
    if (typeof h.forEach === 'function') {
      h.forEach(function (v, k) {
        obj[k] = v;
      });
    } else {
      for (var k in h) if (h.hasOwnProperty(k)) obj[k] = h[k];
    }
    return obj;
  }

  function parseXhrHeaders(raw) {
    var obj = {};
    if (!raw) return obj;
    raw
      .trim()
      .split(/[\r\n]+/)
      .forEach(function (line) {
        var idx = line.indexOf(':');
        if (idx > 0) obj[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      });
    return obj;
  }

  function post(msg) {
    var s = JSON.stringify(msg);
    if (window.FlutterInspectorBridge && window.FlutterInspectorBridge.postMessage) {
      window.FlutterInspectorBridge.postMessage(s);
    } else if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('FlutterInspectorBridge', s);
    }
  }

  function postLog(method, message, stack) {
    var t = truncate(message);
    post({
      t: 'log',
      method: method,
      message: t.v,
      stack: stack,
      page: location.href,
      truncated: t.cut,
    });
  }

  // console.* hooks — call the original method first so the page's own
  // output isn't swallowed, then forward a translated copy.
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (method) {
    var original = console[method];
    console[method] = function () {
      var args = Array.prototype.slice.call(arguments);
      if (original) original.apply(console, args);
      var message = args
        .map(function (a) {
          // Error props are non-enumerable — JSON.stringify yields "{}".
          // String(a) keeps name+message; append the stack when present
          // (worst case V8 repeats the message line, nothing is lost).
          if (a instanceof Error) {
            return String(a) + (a.stack ? '\n' + a.stack : '');
          }
          return typeof a === 'object' ? safeStringify(a) : String(a);
        })
        .join(' ');
      postLog(method, message);
    };
  });

  // window.onerror — chain any existing handler so this bridge never
  // suppresses the page's own error handling.
  var prevOnError = window.onerror;
  window.onerror = function (message, source, lineno, colno, error) {
    postLog('error', String(message), error && error.stack);
    if (prevOnError) return prevOnError.apply(this, arguments);
  };

  // unhandledrejection — a rejected promise nobody caught.
  window.addEventListener('unhandledrejection', function (e) {
    postLog('error', String(e.reason), e.reason && e.reason.stack);
  });

  // fetch — clone the response before reading its body so the page's own
  // consumer still gets an untouched stream.
  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      // fetch(Request) carries its own metadata; fall back to the Request
      // when init doesn't override. (Its body is a one-shot stream, so only
      // an explicit init.body is recorded.)
      var req = input && typeof input === 'object' ? input : null;
      var method = (init && init.method) || (req && req.method) || 'GET';
      var url = typeof input === 'string' ? input : req && req.url;
      var start = Date.now();
      var reqBody = truncate((init && init.body) || undefined);
      var reqHeaders = headersToObject(
        (init && init.headers) || (req && req.headers)
      );
      return originalFetch.apply(this, arguments).then(
        function (res) {
          res
            .clone()
            .text()
            .then(function (resText) {
              var resBodyT = truncate(resText);
              post({
                t: 'net',
                method: method,
                url: url,
                status: res.status,
                durationMs: Date.now() - start,
                reqHeaders: reqHeaders,
                reqBody: reqBody.v,
                resHeaders: headersToObject(res.headers),
                resBody: resBodyT.v,
                truncated: reqBody.cut || resBodyT.cut,
                page: location.href,
                ts: start,
              });
            });
          return res;
        },
        function (err) {
          post({
            t: 'net',
            method: method,
            url: url,
            durationMs: Date.now() - start,
            reqHeaders: reqHeaders,
            reqBody: reqBody.v,
            error: String(err),
            truncated: reqBody.cut,
            page: location.href,
            ts: start,
          });
          throw err;
        }
      );
    };
  }

  // XMLHttpRequest — track method/url on open, timing + response on send.
  var OriginalXHR = window.XMLHttpRequest;
  if (OriginalXHR) {
    var originalOpen = OriginalXHR.prototype.open;
    var originalSend = OriginalXHR.prototype.send;
    OriginalXHR.prototype.open = function (method, url) {
      this.__inspectorMethod = method;
      this.__inspectorUrl = url;
      return originalOpen.apply(this, arguments);
    };
    OriginalXHR.prototype.send = function (body) {
      var xhr = this;
      var start = Date.now();
      var reqBody = truncate(body);
      xhr.addEventListener('loadend', function () {
        // responseText throws on non-text responseType (arraybuffer/blob/json);
        // guard so a binary response still yields a net event, minus its body.
        var rt = xhr.responseType;
        var resBodyT = truncate(rt === '' || rt === 'text' ? xhr.responseText : undefined);
        post({
          t: 'net',
          method: xhr.__inspectorMethod,
          url: xhr.__inspectorUrl,
          status: xhr.status || undefined,
          durationMs: Date.now() - start,
          reqBody: reqBody.v,
          resHeaders: parseXhrHeaders(xhr.getAllResponseHeaders()),
          resBody: resBodyT.v,
          truncated: reqBody.cut || resBodyT.cut,
          page: location.href,
          ts: start,
        });
      });
      return originalSend.apply(this, arguments);
    };
  }
})();
''';
