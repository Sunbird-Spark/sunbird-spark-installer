<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=true; section>
    <#if section = "header">
        <#-- Handled inside the form pane -->
    <#elseif section = "form">
        <div class="spark-form-pane">
            
            <div class="sunbird-logo-wrapper">
                <img src="${url.resourcesPath}/img/sunbird-logo.png" alt="Sunbird" class="sunbird-logo-img" onerror="this.src='https://raw.githubusercontent.com/sunbird-ed/sunbird-ed-portal/master/src/assets/images/sunbird_logo.png'">
            </div>
            
            <!-- STEP 1: IDENTIFY USER -->
            <div id="step-1">
                <h1 class="page-title">Forgot Password?</h1>
                <p class="page-subtitle">Don't worry! Share your details and we will send you a code to reset your password.</p>

                <#if message?has_content>
                    <div class="alert alert-${message.type}">
                        <span class="kc-feedback-text">${message.summary}</span>
                    </div>
                </#if>

                <form id="kc-reset-password-form" method="post" onsubmit="return handleStep1(event)">
                    <div class="kc-form-group">
                        <label for="username" class="kc-label">Email ID / Mobile Number*</label>
                        <div class="input-wrapper">
                            <input type="text" id="username" name="username" class="kc-input" placeholder="Enter Email ID / Mobile Number" autofocus required/>
                        </div>
                    </div>

                    <div class="kc-form-group">
                        <label for="name" class="kc-label">Name*</label>
                        <div class="input-wrapper">
                            <input type="text" id="name" class="kc-input" placeholder="Enter your Name" required/>
                        </div>
                    </div>

                    <div class="kc-form-buttons">
                        <button id="login" class="kc-button" type="submit">Continue</button>
                    </div>
                </form>
                
                <div class="back-to-login">
                    <a href="${url.loginUrl}">${msg("backToLogin")}</a>
                </div>
            </div>

            <!-- STEP 2: VERIFY OTP (Initially Hidden) -->
            <div id="step-2" class="hide">
                <h1 class="page-title text-center">Enter the code</h1>
                <p class="page-subtitle text-center">Enter the 6 digit code sent to your Email ID<br>and complete the verification</p>

                <p class="otp-validity-text text-center">OTP is valid for 30 minutes</p>

                <form id="kc-totp-login-form" method="post" onsubmit="return handleStep2(event)">
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
                        <button class="kc-button block" type="submit">Confirm and Proceed</button>
                    </div>
                </form>
            </div>

            <!-- STEP 3: RESET PASSWORD (Initially Hidden) -->
            <div id="step-3" class="hide">
                <h1 class="page-title">Set New Password</h1>
                <p class="page-subtitle">Create a strong password to secure your account.</p>

                <form id="kc-passwd-update-form" action="${url.loginAction}" method="post">
                    <!-- Keep hidden inputs to satisfy Keycloak form requirements if needed later -->
                    <input type="text" id="username-hidden" name="username" style="display:none;"/>
                    <input type="password" id="password-hidden" name="password" autocomplete="current-password" style="display:none;"/>

                    <div class="kc-form-group">
                        <label for="password-new" class="kc-label">Create New Password*</label>
                        <div class="input-wrapper">
                            <input type="password" id="password-new" name="password-new" class="kc-input" autofocus autocomplete="new-password" placeholder="Enter New Password" required onkeyup="validatePassword()"/>
                            <span class="password-toggle" onclick="togglePassword('password-new', 'eye-icon-new')">
                                <svg id="eye-icon-new" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                            </span>
                        </div>
                    </div>

                    <div class="kc-form-group">
                        <label for="password-confirm" class="kc-label">Confirm Password*</label>
                        <div class="input-wrapper">
                            <input type="password" id="password-confirm" name="password-confirm" class="kc-input" autocomplete="new-password" placeholder="Confirm New Password" required onkeyup="matchPassword()"/>
                            <span class="password-toggle" onclick="togglePassword('password-confirm', 'eye-icon-confirm')">
                                <svg id="eye-icon-confirm" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                            </span>
                        </div>
                    </div>

                    <div class="kc-form-buttons">
                        <button class="kc-button" type="submit">Reset Password</button>
                    </div>
                </form>
            </div>
            
        </div>
        
        <style>
            .hide { display: none !important; }
        </style>

        <script>
            // === STEP HANDLERS ===
            function handleStep1(e) {
                e.preventDefault();
                // Simulation: Assume valid and move to step 2
                document.getElementById('step-1').classList.add('hide');
                document.getElementById('step-2').classList.remove('hide');
                
                // Focus on first OTP digit
                setTimeout(() => {
                    const firstOtp = document.querySelector('.otp-input');
                    if(firstOtp) firstOtp.focus();
                }, 100);
                
                return false;
            }

            function handleStep2(e) {
                e.preventDefault();
                if(collectOtp()){
                     // Simulation: Assume valid OTP and move to step 3
                    document.getElementById('step-2').classList.add('hide');
                    document.getElementById('step-3').classList.remove('hide');
                }
                return false;
            }

            // === OTP LOGIC ===
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
                if(otp.length < 6) return false;
                return true;
            }

            // === PASSWORD TOGGLE LOGIC ===
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
    <#elseif section = "info" >
        <#-- Handled inside the form pane -->
    </#if>
</@layout.registrationLayout>
