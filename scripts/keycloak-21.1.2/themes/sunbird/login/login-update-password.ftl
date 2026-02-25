<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=true; section>
    <#if section = "header">
        <#-- Handled inside the form pane -->
    <#elseif section = "form">
        <div class="spark-form-pane">
            <div class="sunbird-logo-wrapper">
                <img src="${url.resourcesPath}/img/sunbird-logo.png" alt="Sunbird" class="sunbird-logo-img" onerror="this.src='${url.resourcesPath}/img/sunbird-logo.png'">
            </div>
            
            <h1 class="page-title">Set New Password</h1>
            <p class="page-subtitle">Create a strong password to secure your account.</p>

            <#if message?has_content>
                <div class="alert alert-${message.type}">
                    <span class="kc-feedback-text">${message.summary}</span>
                </div>
            </#if>

            <form id="kc-passwd-update-form" class="kc-form" action="${url.loginAction}" method="post">
                <input type="text" id="username" name="username" value="${username}" style="display:none;"/>
                <input type="password" id="password" name="password" autocomplete="current-password" style="display:none;"/>

                <div class="kc-form-group">
                    <label for="password-new" class="kc-label">Create New Password*</label>
                    <div class="input-wrapper">
                        <input type="password" id="password-new" name="password-new" class="kc-input" autofocus autocomplete="new-password" placeholder="Enter New Password" required onkeyup="validatePassword()"/>
                        <span class="password-toggle" onclick="togglePassword('password-new', 'eye-icon-new')">
                            <svg id="eye-icon-new" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        </span>
                    </div>
                    <div id="passwd-error-msg" class="ui text passwdchk">Your password must contain a minimum of 8 characters. It must include numerals, lower and upper case alphabets and special characters, without any spaces</div>
                </div>

                <div class="kc-form-group">
                    <label for="password-confirm" class="kc-label">Confirm Password*</label>
                    <div class="input-wrapper">
                        <input type="password" id="password-confirm" name="password-confirm" class="kc-input" autocomplete="new-password" placeholder="Confirm New Password" required onkeyup="matchPassword()"/>
                        <span class="password-toggle" onclick="togglePassword('password-confirm', 'eye-icon-confirm')">
                            <svg id="eye-icon-confirm" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        </span>
                    </div>
                    <div id="passwd-match-error-msg" class="ui text confpasswderr hide">Passwords do not match</div>
                </div>

                <div class="kc-form-buttons">
                    <button id="login" class="kc-button" type="button" onclick="return handleUpdateSubmit(event)">Reset Password</button>
                </div>
            </form>
        </div>

        <script>
            function handleUpdateSubmit(e) {
                e.preventDefault();
                var p1El = document.getElementById('password-new');
                var p2El = document.getElementById('password-confirm');
                var p1 = p1El ? String(p1El.value || '').trim() : '';
                var p2 = p2El ? String(p2El.value || '').trim() : '';
                if (!p1) {
                    if (window.showToast) window.showToast('error', 'Enter New Password');
                    return false;
                }
                if (!p2) {
                    if (window.showToast) window.showToast('error', 'Confirm New Password');
                    return false;
                }
                var hasLength = p1.length >= 8;
                var hasLower = /[a-z]/.test(p1);
                var hasUpper = /[A-Z]/.test(p1);
                var hasNumber = /[0-9]/.test(p1);
                var hasSpecial = /[\W_]/.test(p1);
                var noSpaces = /^\S*$/.test(p1);
                var isComplex = hasLength && hasLower && hasUpper && hasNumber && hasSpecial && noSpaces;
                if (!isComplex) {
                    if (window.showToast) window.showToast('error', 'Your password must contain a minimum of 8 characters. It must include numerals, lower and upper case alphabets and special characters, without any spaces');
                    return false;
                }
                if (p1 !== p2) {
                    if (window.showToast) window.showToast('error', 'Passwords do not match');
                    return false;
                }
                var form = document.getElementById('kc-passwd-update-form');
                if (form && form.checkValidity && form.checkValidity()) {
                    if (form.requestSubmit) form.requestSubmit(); else form.submit();
                } else {
                    if (window.showToast) window.showToast('error', 'Please fix the highlighted fields');
                }
                return false;
            }
            function togglePassword(id, iconId) {
                const passwordInput = document.getElementById(id);
                const eyeIcon = document.getElementById(iconId);
                
                if (passwordInput.type === 'password') {
                    passwordInput.type = 'text';
                    eyeIcon.innerHTML = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/><line x1="1" y1="1" x2="23" y2="23" stroke="currentColor"/>';
                } else {
                    passwordInput.type = 'password';
                    eyeIcon.innerHTML = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
                }
            }
        </script>
        <style>
            .hide { display: none !important; }
        </style>
</@layout.registrationLayout>
