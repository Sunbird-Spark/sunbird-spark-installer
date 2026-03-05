<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <#if messageHeader??>
        <#-- ${messageHeader} -->
        <#else>
        <#-- ${message.summary} -->
        </#if>
    <#elseif section = "form">
        <div id="kc-info-message">
<!--           <p class="instruction">${message.summary}<#if requiredActions??><#list requiredActions>: <b><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#items></b></#list><#else></#if></p> -->
             <#if skipLink??>
             <#else>
               <#if actionUri??>
                 <div class="ui text active centered inline large loader">Loading.. Please wait..</div>
                 <div id="kc-info-message-hide" style="display:none">
                   <p><a id="click-here-to-proceed" href="${actionUri}">${kcSanitize(msg("proceedWithAction"))?no_esc}</a></p>
                   <script type="text/javascript">
                     window.onload = function(){
                       function autoClick() {
                         document.getElementById("click-here-to-proceed").click();
                       }
                     setInterval(autoClick, 500);
                     }
                   </script>
                 </div>
               <#elseif pageRedirectUri??>
                 <style>body { visibility: hidden !important; }</style>
                 <p><a href="${pageRedirectUri}" class="kc-button">${kcSanitize(msg("backToApplication"))?no_esc}</a></p>
                 <script type="text/javascript">
                   window.location.href = "${pageRedirectUri}";
                 </script>
               <#elseif client.baseUrl??>
                 <p><a href="${client.baseUrl}" class="kc-button">${kcSanitize(msg("backToApplication"))?no_esc}</a></p>
               </#if>
             </#if>
        </div>
    </#if>
</@layout.registrationLayout>
