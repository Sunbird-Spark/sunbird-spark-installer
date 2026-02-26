<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}" lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="robots" content="noindex, nofollow">
    <meta http-equiv="cache-control" content="max-age=0" />
    <meta http-equiv="cache-control" content="no-cache" />
    <meta http-equiv="Cache-Control" content="no-store" />
    <meta http-equiv="pragma" content="no-cache" />
    <meta name="last-modified" content="2019-01-17 15:30:17 +0530">
    <meta http-equiv="Expires" content="600" />
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>
    <title>Log in to Sunbird</title>
    <link rel="icon" type="image/png" sizes="32x32" href="${url.resourcesPath}/img/fav.png" />
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    
    <#-- Hide already logged in messages immediately -->
    <style type="text/css">
        .toast-container .toast:has(.toast-message:contains("already logged in")),
        .toast-container .toast:has(.toast-message:contains("Already logged in")) {
            display: none !important;
        }
        
        /* Fallback for browsers that don't support :has() */
        .toast-container .toast {
            transition: opacity 0.1s;
        }
        
        .toast-container .toast.hide-already-logged-in {
            display: none !important;
        }
    </style>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
            <#if script?contains('jquery')>
                <script type="text/javascript">
                    (function() {
                        if (window.jQuery) {
                            var originalAjax = jQuery.ajax;
                            jQuery.ajax = function(options) {
                                if (options.url && options.url.indexOf('/api/org/v2/search') !== -1) {
                                    var deferred = jQuery.Deferred();
                                    var mockResponse = {
                                        "responseCode": "OK",
                                        "result": {
                                            "response": {
                                                "content": [{
                                                    "hashTagId": "sunbird",
                                                    "status": 1,
                                                    "isTenant": true,
                                                    "slug": "sunbird"
                                                }]
                                            }
                                        }
                                    };
                                    setTimeout(function() {
                                        if (options.success) options.success(mockResponse);
                                        deferred.resolve(mockResponse);
                                    }, 10);
                                    return deferred.promise();
                                }
                                return originalAjax.apply(this, arguments);
                            };
                        }
                    })();
                </script>
            </#if>
        </#list>
    </#if>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>
    
    <#-- Early redirect check for already logged in users -->
    <#if displayMessage && message?has_content>
    <script type="text/javascript">
        // Early redirect check - runs immediately in head
        (function() {
            try {
                var summary = '${message.summary?js_string}';
                if (summary && summary.toLowerCase().indexOf('already logged in') !== -1) {
                    console.log('Early redirect: Already logged in detected');
                    
                    // Get redirect parameters
                    var urlParams = new URLSearchParams(window.location.search);
                    var redirect_uri = urlParams.get('redirect_uri') || sessionStorage.getItem('redirect_uri');
                    var state = urlParams.get('state');
                    
                    if (redirect_uri) {
                        try {
                            redirect_uri = decodeURIComponent(redirect_uri);
                        } catch (e) {}
                        
                        var redirectUrl = redirect_uri;
                        if (state) {
                            var separator = redirect_uri.indexOf('?') !== -1 ? '&' : '?';
                            redirectUrl += separator + 'state=' + encodeURIComponent(state);
                        }
                        
                        console.log('Early redirect to:', redirectUrl);
                        window.location.replace(redirectUrl);
                        return;
                    }
                    
                    // Fallback to client base URL
                    var base = '${client.baseUrl!}';
                    if (base && base.length > 0) {
                        console.log('Early redirect to client base:', base);
                        window.location.replace(base);
                        return;
                    }
                    
                    // Last resort
                    window.location.replace('/');
                }
            } catch (e) {
                console.error('Early redirect error:', e);
            }
        })();
    </script>
    </#if>
</head>

<body class="${properties.kcBodyClass!}">
    <main class="login-main">
        <div class="login-wrapper">
            <div class="login-split-container">
                <div class="login-left-panel">
                    <div class="login-left-panel-container">
                    <div class="background-pattern" style="background-image: url('${url.resourcesPath}/img/auth-wave-bg.png');"></div>
                    <div class="left-panel-content">
                        <h2 class="left-panel-title">Empower your future<br/>through learning.</h2>
                    </div>
                    </div>
                </div>
                <div class="login-right-panel">
                    <div class="login-card">
                    <!-- Close Button -->
                    <button class="close-button" onclick="window.history.back();" aria-label="Close">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <path d="M18 6L6 18M6 6L18 18" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        </svg>
                    </button>

    <div id="kc-container" class="${properties.kcContainerClass!}">
        <div id="kc-container-wrapper" class="${properties.kcContainerWrapperClass!}">

            <div id="kc-header" class="${properties.kcHeaderClass!}">
                <div id="kc-header-wrapper" class="${properties.kcHeaderWrapperClass!}"><#nested "header"></div>
            </div>

            <#if realm.internationalizationEnabled>
                <div id="kc-locale" class="${properties.kcLocaleClass!}">
                    <div id="kc-locale-wrapper" class="${properties.kcLocaleWrapperClass!}">
                        <div class="kc-dropdown" id="kc-locale-dropdown">
                            <a href="#" id="kc-current-locale-link">${locale.current}</a>
                            <ul>
                                <#list locale.supported as l>
                                    <li class="kc-dropdown-item"><a href="${l.url}">${l.label}</a></li>
                                </#list>
                            </ul>
                        </div>
                    </div>
                </div>
            </#if>

            <div id="kc-content" class="${properties.kcContentClass!}">
                <div id="kc-content-wrapper" class="${properties.kcContentWrapperClass!}">
                    <#if displayMessage && message?has_content>
                        <!--div class="${properties.kcFeedbackAreaClass!}">
                            <div class="alert alert-${message.type}">
                                <#if message.type = 'success'><span class="${properties.kcFeedbackSuccessIcon!}"></span></#if>
                                <#if message.type = 'warning'><span class="${properties.kcFeedbackWarningIcon!}"></span></#if>
                                <#if message.type = 'error'><span class="${properties.kcFeedbackErrorIcon!}"></span></#if>
                                <#if message.type = 'info'><span class="${properties.kcFeedbackInfoIcon!}"></span></#if>
                                <span class="kc-feedback-text">${message.summary}</span>
                            </div>
                        </div-->
                    </#if>

                    <div id="kc-form" class="${properties.kcFormAreaClass!}">
                        <div id="kc-form-wrapper" class="${properties.kcFormAreaWrapperClass!}">
                            <#nested "form">
                        </div>
                    </div>
                    <script type="text/javascript">
                        var sessionTenant = sessionStorage.getItem("rootTenantLogo");
                        
                        if(sessionTenant){
                            var imgSrc = "${url.resourcesPath}/img/tenants/"+sessionTenant+".png";
                        }else{
                            var imgSrc = "${url.resourcesPath}/img/logo.png";
                        }

                        var logoImg =  document.querySelector(".ui.header img");
                        if(logoImg){
                            logoImg.setAttribute('class','logo-image');
                            if(sessionTenant) {
                                var logoname = sessionTenant + 'logo';
                                logoImg.setAttribute('alt',logoname);
                            } else {
                                var logoname = 'Sunbird logo';
                                logoImg.setAttribute('alt',logoname);
                            }
                            logoImg.src = imgSrc;
                            logoImg.addEventListener("error", ()=>{ logoImg.onerror=null;logoImg.src='${url.resourcesPath}/img/logo.png'});
                        }

                    </script>
                    <#if displayInfo>
                        <div id="kc-info" class="${properties.kcInfoAreaClass!}">
                            <div id="kc-info-wrapper" class="${properties.kcInfoAreaWrapperClass!}">
                                <#nested "info">
                            </div>
                        </div>
                    </#if>
                </div>
            </div>
        </div>
    </div>
                    </div><!-- Close login-card -->
                </div><!-- Close login-right-panel -->
            </div><!-- Close login-split-container -->
        </div><!-- Close login-wrapper -->
    </main>
    <div class="toast-container"></div>
    <script type="text/javascript">
        if (!window.showToast) {
            window.showToast = function (type, text, duration, title) {
                try {
                    // Don't show toast for "already logged in" messages
                    if (text && text.toLowerCase().indexOf('already logged in') !== -1) {
                        console.log('Suppressing already logged in toast message');
                        return null;
                    }
                    
                    var container = document.querySelector('.toast-container');
                    if (!container) {
                        container = document.createElement('div');
                        container.className = 'toast-container';
                        container.setAttribute('aria-live', 'polite');
                        container.setAttribute('aria-atomic', 'true');
                        document.body.appendChild(container);
                    }
                    var cls = 'toast';
                    if (type) cls += ' toast-' + String(type).toLowerCase();
                    var toast = document.createElement('div');
                    toast.className = cls;
                    toast.setAttribute('role', 'status');
                    var t = document.createElement('div');
                    t.className = 'toast-title';
                    t.textContent = title || (String(type).toLowerCase() === 'error' ? 'Error' : '');
                    var msg = document.createElement('div');
                    msg.className = 'toast-message';
                    msg.textContent = text || '';
                    var close = document.createElement('button');
                    close.className = 'toast-close';
                    close.setAttribute('aria-label', 'Close');
                    close.innerHTML = '&times;';
                    toast.appendChild(t);
                    toast.appendChild(msg);
                    toast.appendChild(close);
                    container.appendChild(toast);
                    setTimeout(function () { toast.classList.add('show'); }, 10);
                    var hide = function () {
                        toast.classList.remove('show');
                        setTimeout(function () { toast.remove(); }, 200);
                    };
                    close.addEventListener('click', hide);
                    setTimeout(hide, Number(duration) || 5000);
                    return toast;
                } catch (e) { /* no-op */ }
            };
        }
    </script>
    <#if displayMessage && message?has_content>
    <script type="text/javascript">
        if (window.showToast) {
            window.showToast('${message.type}', '${message.summary?js_string}');
        }
    </script>
    <script type="text/javascript">
        // Function to get value from session storage (similar to telemetry service)
        function getValueFromSession(key) {
            try {
                var urlParams = new URLSearchParams(window.location.search);
                var value = urlParams.get(key);
                if (value) {
                    sessionStorage.setItem(key, value);
                    return value;
                } else {
                    return sessionStorage.getItem(key);
                }
            } catch (e) {
                console.error('Error getting value from session:', e);
                return null;
            }
        }
        
        // Immediate execution - don't wait for DOM ready
        (function () {
            try {
                var summary = '${message.summary?js_string}';
                console.log('Checking message summary:', summary);
                
                if (summary && summary.toLowerCase().indexOf('already logged in') !== -1) {
                    console.log('Already logged in detected, initiating redirect...');
                    
                    // Hide any existing toast/modal immediately
                    var toastContainer = document.querySelector('.toast-container');
                    if (toastContainer) {
                        toastContainer.style.display = 'none';
                    }
                    
                    // When already logged in, we should redirect back to the application
                    // First, try to get redirect_uri from current URL
                    var urlParams = new URLSearchParams(window.location.search);
                    var redirect_uri = urlParams.get('redirect_uri');
                    var state = urlParams.get('state');
                    var client_id = urlParams.get('client_id');
                    
                    console.log('URL params - redirect_uri:', redirect_uri, 'state:', state, 'client_id:', client_id);
                    
                    // Use the same redirect logic as the telemetry service
                    if (typeof getValueFromSession === 'function') {
                        redirect_uri = getValueFromSession('redirect_uri') || redirect_uri;
                    }
                    
                    console.log('Final redirect_uri:', redirect_uri);
                    
                    if (redirect_uri) {
                        // Decode the redirect_uri if it's encoded
                        try {
                            redirect_uri = decodeURIComponent(redirect_uri);
                        } catch (e) {
                            // If decoding fails, use as is
                            console.log('Could not decode redirect_uri, using as is');
                        }
                        
                        // For already logged in scenario, redirect to the application
                        // Add any necessary parameters
                        var redirectUrl = redirect_uri;
                        if (state) {
                            var separator = redirect_uri.indexOf('?') !== -1 ? '&' : '?';
                            redirectUrl += separator + 'state=' + encodeURIComponent(state);
                        }
                        
                        console.log('Redirecting already logged in user to:', redirectUrl);
                        
                        // Use replace instead of href to avoid back button issues
                        window.location.replace(redirectUrl);
                        return;
                    }
                    
                    // Fallback: try client base URL
                    var base = '${client.baseUrl!}';
                    if (base && base.length > 0) {
                        console.log('Redirecting to client base URL:', base);
                        window.location.replace(base);
                        return;
                    }
                    
                    // Last resort: redirect to root
                    console.log('Redirecting to root as last resort');
                    window.location.replace('/');
                }
            } catch (e) {
                console.error('Error in already logged in redirect:', e);
                // Fallback redirect
                var base = '${client.baseUrl!}';
                if (base && base.length > 0) {
                    window.location.replace(base);
                } else {
                    window.location.replace('/');
                }
            }
        })();
    </script>
    </#if>
</body>
</html>
</#macro>
