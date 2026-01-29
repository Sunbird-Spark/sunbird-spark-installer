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
                    <label for="name" class="kc-label">Name*</label>
                    <div class="input-wrapper">
                        <input type="text" id="name" class="kc-input" placeholder="Enter your Name" required/>
                    </div>
                </div>

                <div class="kc-form-buttons">
                    <button id="login" class="kc-button" type="submit" onclick="javascript:makeDivUnclickable()">Continue</button>
                </div>
            </form>
            
            <div class="back-to-login">
                <a href="${url.loginUrl}">${msg("backToLogin")}</a>
            </div>
        </div>
    <#elseif section = "info" >
        <#-- Handled inside the form pane -->
    </#if>
</@layout.registrationLayout>
