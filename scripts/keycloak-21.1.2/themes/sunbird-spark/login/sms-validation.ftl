<#import "template.ftl" as layout>
<@layout.registrationLayout; section>
    <#if section = "header">
        <#-- Handled inside the form pane -->
    <#elseif section = "form">
        <div class="spark-form-pane validation-pane">
            
            <div class="sunbird-logo-wrapper">
                <img src="${url.resourcesPath}/img/sunbird-logo.png" alt="Sunbird" class="sunbird-logo-img" onerror="this.src='https://raw.githubusercontent.com/sunbird-ed/sunbird-ed-portal/master/src/assets/images/sunbird_logo.png'">
            </div>
            
            <h1 class="page-title text-center">Enter the code</h1>
            <p class="page-subtitle text-center">Enter the 6 digit code sent to your Email ID<br>and complete the verification</p>

            <#if message?has_content>
                <div class="alert alert-${message.type} text-center mb-4">
                    <span class="kc-feedback-text">${message.summary}</span>
                </div>
            </#if>

            <p class="otp-validity-text text-center">OTP is valid for 30 minutes</p>

            <form id="kc-totp-login-form" class="kc-form" action="${url.loginAction}" method="post">
                <div class="otp-container">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); focusNext(this)" onkeydown="handleBackspace(this, event)">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); focusNext(this)" onkeydown="handleBackspace(this, event)">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); focusNext(this)" onkeydown="handleBackspace(this, event)">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); focusNext(this)" onkeydown="handleBackspace(this, event)">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); focusNext(this)" onkeydown="handleBackspace(this, event)">
                    <input type="text" class="otp-input" maxlength="1" pattern="[0-9]" inputmode="numeric" required oninput="this.value = this.value.replace(/[^0-9]/g, ''); collectOtp()" onkeydown="handleBackspace(this, event)">
                    
                    <!-- Hidden input to store the actual concatenated OTP -->
                    <input id="totp" name="smsCode" type="hidden" />
                </div>

                <div class="resend-otp-container text-center">
                    <span id="timer">00:00</span> <a href="#" id="resend-link" onclick="resendOtp(); return false;">Resend OTP</a>
                </div>

                <div class="kc-form-buttons">
                    <button class="kc-button block" type="submit" onclick="return collectOtp()">Confirm and Proceed</button>
                </div>
            </form>
            
            <script>
                function focusNext(el) {
                    if (el.value.length === 1) {
                        const next = el.nextElementSibling;
                        if (next && next.classList.contains('otp-input')) {
                            next.focus();
                        }
                    }
                }
                
                function handleBackspace(el, event) {
                    if (event.key === 'Backspace' && el.value.length === 0) {
                        const prev = el.previousElementSibling;
                        if (prev && prev.classList.contains('otp-input')) {
                            prev.focus();
                        }
                    }
                }

                function collectOtp() {
                    const inputs = document.querySelectorAll('.otp-input');
                    let otp = '';
                    inputs.forEach(input => otp += input.value);
                    document.getElementById('totp').value = otp;
                    return true;
                }
            </script>
        </div>
    <#elseif section = "info" >
        <div class="registration-link">
            <#if client?? && client.baseUrl?has_content>
                <a id="backToApplication" href="${client.baseUrl}">${msg("backToApplication")}</a>
            </#if>
        </div>
    </#if>
</@layout.registrationLayout>
