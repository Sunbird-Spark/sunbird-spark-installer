<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=true; section>
    <#if section = "header">
        <#-- Handled inside the form pane -->
    <#elseif section = "form">
        <div class="spark-form-pane">
            
            <div class="sunbird-logo-wrapper">
                <img src="${url.resourcesPath}/img/sunbird-logo.png" alt="Sunbird" class="sunbird-logo-img" onerror="this.src='https://raw.githubusercontent.com/sunbird-ed/sunbird-ed-portal/master/src/assets/images/sunbird_logo.png'">
            </div>
            
            <h1 class="page-title">Forgot Password?</h1>
            <p class="page-subtitle">Don't worry! Share your details and we will send you a code to reset your password.</p>

            <#if message?has_content>
                <div class="alert alert-${message.type}">
                    <span class="kc-feedback-text">${message.summary}</span>
                </div>
            </#if>

            <form id="kc-reset-password-form" action="${url.loginAction}" method="post">
                <div class="kc-form-group">
                    <label for="username" class="kc-label">Email ID / Mobile Number*</label>
                    <div class="input-wrapper">
                        <input type="text" id="username" name="username" class="kc-input" placeholder="Enter Email ID / Mobile Number" autofocus required/>
                    </div>
                </div>

                <div class="kc-form-group">
                    <label for="password-new" class="kc-label">Set Password*</label>
                    <div class="input-wrapper">
                        <input type="password" id="password-new" name="password-new" class="kc-input" placeholder="Enter Password" required/>
                        <span class="password-toggle" onclick="togglePassword('password-new')">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        </span>
                    </div>
                </div>

                <div class="kc-form-group">
                    <label for="password-confirm" class="kc-label">Confirm Password*</label>
                    <div class="input-wrapper">
                        <input type="password" id="password-confirm" name="password-confirm" class="kc-input" placeholder="Re-enter Password" required/>
                        <span class="password-toggle" onclick="togglePassword('password-confirm')">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        </span>
                    </div>
                </div>

                <div class="kc-form-buttons">
                    <button class="kc-button" type="submit">Continue</button>
                </div>
            </form>

            <script>
                function togglePassword(id) {
                    const el = document.getElementById(id);
                    el.type = el.type === "password" ? "text" : "password";
                }
            </script>
        </div>
    <#elseif section = "info" >
        <#-- Handled inside the form pane -->
    </#if>
</@layout.registrationLayout>
