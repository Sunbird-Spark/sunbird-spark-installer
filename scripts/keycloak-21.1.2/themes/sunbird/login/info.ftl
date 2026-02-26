<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <#if messageHeader??>
        ${messageHeader}
        <#else>
        ${message.summary}
        </#if>
    <#elseif section = "form">
    <div id="kc-info-message">
        <p class="instruction">${message.summary}<#if requiredActions??><#list requiredActions>: <b><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#items></b></#list><#else></#if></p>
        <#if skipLink??>
        <#else>
            <#if pageRedirectUri??>
                <p><a href="${pageRedirectUri}">${kcSanitize(msg("backToApplication"))?no_esc}</a></p>
            <#elseif actionUri??>
                <p><a href="${actionUri}">${kcSanitize(msg("proceedWithAction"))?no_esc}</a></p>
            <#elseif client.baseUrl??>
                <p><a href="${client.baseUrl}">${kcSanitize(msg("backToApplication"))?no_esc}</a></p>
            </#if>
        </#if>
    </div>
    
    <#-- Handle "already logged in" scenario with automatic redirect -->
    <#if message?has_content>
    <script type="text/javascript">
        // Function to get value from session storage
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
                // Check if this is a password reset success
                var isResetSuccess = sessionStorage.getItem('sb_redirect_reset_success');
                if (isResetSuccess === '1') {
                    console.log('Password reset success detected, redirecting to portal...');
                    sessionStorage.removeItem('sb_redirect_reset_success');
                    
                    var redirect_uri = getValueFromSession('redirect_uri');
                    var client_id = new URLSearchParams(window.location.search).get('client_id');
                    
                    if (redirect_uri) {
                        try {
                            var redirect_uriLocation = new URL(redirect_uri);
                            var redirectUrl = redirect_uriLocation.protocol + '//' + redirect_uriLocation.host + '/password-reset-success';
                            console.log('Redirecting to:', redirectUrl);
                            window.location.href = redirectUrl;
                            return;
                        } catch (e) {
                            console.error('Error parsing redirect_uri:', e);
                        }
                    }
                    
                    // Fallback to current host
                    window.location.href = window.location.protocol + '//' + window.location.host + '/password-reset-success';
                    return;
                }
                
                var summary = '${message.summary?js_string}';
                console.log('Info page - Checking message summary:', summary);
                
                if (summary && summary.toLowerCase().indexOf('already logged in') !== -1) {
                    console.log('Already logged in detected on info page, initiating redirect...');
                    
                    // When already logged in, redirect back to the application
                    var urlParams = new URLSearchParams(window.location.search);
                    var redirect_uri = urlParams.get('redirect_uri');
                    var state = urlParams.get('state');
                    var client_id = urlParams.get('client_id');
                    
                    console.log('URL params - redirect_uri:', redirect_uri, 'state:', state, 'client_id:', client_id);
                    
                    // Try to get redirect_uri from session storage
                    redirect_uri = getValueFromSession('redirect_uri') || redirect_uri;
                    
                    console.log('Final redirect_uri:', redirect_uri);
                    
                    if (redirect_uri) {
                        // Decode the redirect_uri if it's encoded
                        try {
                            redirect_uri = decodeURIComponent(redirect_uri);
                        } catch (e) {
                            // If decoding fails, use as is
                            console.log('Could not decode redirect_uri, using as is');
                        }
                        
                        // Add state parameter if present
                        var redirectUrl = redirect_uri;
                        if (state) {
                            var separator = redirect_uri.indexOf('?') !== -1 ? '&' : '?';
                            redirectUrl += separator + 'state=' + encodeURIComponent(state);
                        }
                        
                        console.log('Redirecting already logged in user to:', redirectUrl);
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
    </#if>
</@layout.registrationLayout>