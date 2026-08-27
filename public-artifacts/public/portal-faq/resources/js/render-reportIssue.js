var selectedLang = getUrlVars()["selectedlang"];
var SUPPORTED_LANGS = ['en', 'hi', 'kn', 'fr', 'gu', 'te', 'as', 'ar', 'or', 'mr', 'bn', 'ta', 'ur', 'pt', 'pa'];
console.log('selected Lang', selectedLang);
$(document).ready(function () {
    var jsonUrl;
    var normalizedLang = selectedLang ? selectedLang.trim().toLowerCase() : '';
    if (normalizedLang && SUPPORTED_LANGS.indexOf(normalizedLang) !== -1) {
        jsonUrl = "./resources/res/faq-" + normalizedLang + ".json"
    } else {
        jsonUrl = "./resources/res/faq-en.json"
    }

    console.log(jsonUrl);
    $.getJSON(jsonUrl, function (data) {
        var headerDiv = document.createElement('div');
        headerDiv.className = 'help-header-send-email';
        var headerTitle = document.createElement('h4');
        headerTitle.textContent = data.constants.reportIssue;
        var headerMsg = document.createElement('p');
        headerMsg.textContent = data.constants.explainMsg;
        headerDiv.appendChild(headerTitle);
        headerDiv.appendChild(headerMsg);

        var infoDiv = document.createElement('div');
        infoDiv.className = 'info-msg-send-email';
        var infoMsg = document.createElement('p');
        infoMsg.textContent = data.constants.tellMoreMsg;
        infoDiv.appendChild(infoMsg);

        var formWrapper = document.createElement('div');
        formWrapper.className = 'send-email-form';

        var form = document.createElement('form');
        form.setAttribute('action', '#');
        form.id = 'send-email-form';

        var textareaDiv = document.createElement('div');
        textareaDiv.id = 'textareadiv';
        var textarea = document.createElement('textarea');
        textarea.setAttribute('type', 'text');
        textarea.name = 'moreInfo';
        textarea.placeholder = data.constants.typeHere;
        textarea.className = 'input-text-form';
        textarea.maxLength = 1000;
        var textareaInfo = document.createElement('p');
        textareaInfo.id = 'textareainfo';
        textareaInfo.appendChild(document.createTextNode(' '));
        var charLeft = document.createElement('span');
        charLeft.id = 'charleft';
        charLeft.textContent = '1000';
        textareaInfo.appendChild(charLeft);
        textareaInfo.appendChild(document.createTextNode(' ' + data.constants.charactersLeft));
        textareaDiv.appendChild(textarea);
        textareaDiv.appendChild(textareaInfo);

        var initiateInfo = document.createElement('div');
        initiateInfo.className = 'initiate-email-info';
        var sendEmailInfo = document.createElement('p');
        sendEmailInfo.className = 'send-email-info';
        sendEmailInfo.textContent = data.constants.triggerEmailMsg;
        var initiateBtnWrap = document.createElement('div');
        initiateBtnWrap.className = 'initiate-email-info-button';
        var initiateInput = document.createElement('input');
        initiateInput.type = 'submit';
        initiateInput.value = data.constants.initiateEmailButton;
        initiateInput.className = 'submit-button';
        initiateInput.id = 'initiate-email';
        initiateBtnWrap.appendChild(initiateInput);
        initiateInfo.appendChild(sendEmailInfo);
        initiateInfo.appendChild(initiateBtnWrap);

        form.appendChild(textareaDiv);
        form.appendChild(initiateInfo);
        formWrapper.appendChild(form);

        var fragment = document.createDocumentFragment();
        fragment.appendChild(headerDiv);
        fragment.appendChild(infoDiv);
        fragment.appendChild(formWrapper);

        $('#loading').replaceWith(fragment);
    });
});

function getUrlVars() {
    var vars = [], hash;
    var hashes = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
    for (var i = 0; i < hashes.length; i++) {
        hash = hashes[i].split('=');
        vars.push(hash[0]);
        vars[hash[0]] = hash[1];
    }
    return vars;
}
