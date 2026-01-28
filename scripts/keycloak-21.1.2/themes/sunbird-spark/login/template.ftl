<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}">
<html lang="en">
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
    <title><#nested "title"></title>
    <link rel="icon" href="${url.resourcesPath}/img/favicon.ico" />
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>
</head>

<body class="${properties.kcBodyClass!}">
    <main class="login-main">
        <div class="login-wrapper">
            <div class="login-split-container">
                <div class="login-left-panel">
                    <div class="login-left-panel-container">
                    <div class="background-pattern" style="background-image: url('${url.resourcesPath}/img/wave.svg');"></div>
                    <div class="left-panel-content">
                        <h2 class="left-panel-title">Empower your future through learning.</h2>
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
</body>
</html>
</#macro>
