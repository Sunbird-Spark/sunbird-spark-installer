<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=social.displayInfo; section>
    <#if section = "header">
        <div class="login-header">
            <div class="sunbird-logo">
                <img src="${url.resourcesPath}/img/sunbird-logo.png" alt="Sunbird Logo" />
            </div>
            <h1 class="welcome-title">Welcome to Sunbird!</h1>
            <p class="welcome-subtitle">Your learning journey starts here—log in to continue.</p>
        </div>
    <#elseif section = "form">
    <div id="kc-form" <#if realm.password && social.providers??>class="${properties.kcContentWrapperClass!}"</#if>>
      <div id="kc-form-wrapper" <#if realm.password && social.providers??>class="${properties.kcFormSocialAccountContentClass!} ${properties.kcFormSocialAccountClass!}"</#if>>
        
        <#-- Google Sign In Button (if social providers exist) -->
        <#if social.providers??>
            <div id="kc-social-providers-top">
                <#list social.providers as p>
                    <#if p.providerId == "google">
                        <a href="${p.loginUrl}" id="google-login-button" class="google-signin-btn" onclick="navigate('google'); return false;">
                            <img src="${url.resourcesPath}/img/google-icon.svg" alt="Google" class="google-icon" />
                            <span>Sign in with Google</span>
                        </a>
                    </#if>
                </#list>
            </div>
            
            <#-- OR Divider -->
            <div class="or-divider">
                <span>OR</span>
            </div>
        </#if>
        
        <#if realm.password>
            <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                <div class="${properties.kcFormGroupClass!}">
                    <label for="emailormobile" class="${properties.kcLabelClass!}">Email ID / Mobile Number</label>

                    <#if usernameEditDisabled??>
                        <input tabindex="1" id="emailormobile" class="${properties.kcInputClass!}" name="username" value="${(login.username!'')}" type="text" disabled placeholder="Enter Email ID / Mobile Number" />
                    <#else>
                        <input tabindex="1" id="emailormobile" class="${properties.kcInputClass!}" name="username" value="${(login.username!'')}" onfocusin="inputBoxFocusIn(this)" onfocusout="inputBoxFocusOut(this)" type="text" autofocus autocomplete="username" placeholder="Enter Email ID / Mobile Number" />
                    </#if>
                </div>

                <div class="${properties.kcFormGroupClass!}">
                    <label for="password" class="${properties.kcLabelClass!}">Password</label>
                    <div class="password-wrapper">
                        <input tabindex="2" id="password" class="${properties.kcInputClass!}" name="password" type="password" onfocusin="inputBoxFocusIn(this)" onfocusout="inputBoxFocusOut(this)" autocomplete="current-password" placeholder="Enter Password" />
                        <button type="button" class="password-toggle" onclick="togglePassword()" aria-label="Toggle password visibility">
                            <svg id="eye-icon" width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                                <path d="M10 4C4.5 4 1.5 10 1.5 10C1.5 10 4.5 16 10 16C15.5 16 18.5 10 18.5 10C18.5 10 15.5 4 10 4Z" stroke="#666" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                                <circle cx="10" cy="10" r="3" stroke="#666" stroke-width="1.5"/>
                            </svg>
                        </button>
                    </div>
                </div>

                <div class="forgot-password">
                    <#if realm.resetPasswordAllowed>
                        <a id="fgtKeycloakFlow" class="hide" tabindex="3" onclick="javascript:storeLocation(); javascript:makeDivUnclickable(); javascript:storeForgotPasswordLocation(event);" href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
                        <a id="fgtPortalFlow" class="hide" tabindex="3" href="#" onclick="javascript:makeDivUnclickable(); javascript:createTelemetryEvent(event); javascript:forgetPassword('/forgot-password'); return false;">${msg("doForgotPassword")}</a>
                    </#if>
                </div>

                <div id="kc-form-buttons" class="${properties.kcFormGroupClass!}">
                    <button tabindex="4" class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!} login-button" name="login" id="kc-login" type="submit" onclick="doLogin(event)">Login</button>
                </div>
            </form>
        </#if>
        </div>
      </div>
    <#elseif section = "info" >
        <#if realm.password && realm.registrationAllowed && !usernameEditDisabled??>
            <div id="kc-registration" class="registration-link">
                <span>New user? Please <a tabindex="5" onclick=navigate('self')>create an account</a> to continue.</span>
            </div>
        </#if>
    </#if>

    <#-- JavaScript for password toggle -->
    <script>
        function togglePassword() {
            const passwordInput = document.getElementById('password');
            const eyeIcon = document.getElementById('eye-icon');
            
            if (passwordInput.type === 'password') {
                passwordInput.type = 'text';
                eyeIcon.innerHTML = '<path d="M10 4C4.5 4 1.5 10 1.5 10C1.5 10 4.5 16 10 16C15.5 16 18.5 10 18.5 10C18.5 10 15.5 4 10 4Z" stroke="#666" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="10" cy="10" r="3" stroke="#666" stroke-width="1.5"/><line x1="2" y1="2" x2="18" y2="18" stroke="#666" stroke-width="1.5" stroke-linecap="round"/>';
            } else {
                passwordInput.type = 'password';
                eyeIcon.innerHTML = '<path d="M10 4C4.5 4 1.5 10 1.5 10C1.5 10 4.5 16 10 16C15.5 16 18.5 10 18.5 10C18.5 10 15.5 4 10 4Z" stroke="#666" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="10" cy="10" r="3" stroke="#666" stroke-width="1.5"/>';
            }
        }
    </script>

</@layout.registrationLayout>
