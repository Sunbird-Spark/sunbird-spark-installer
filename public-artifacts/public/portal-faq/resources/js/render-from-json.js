var selectedLang = getUrlVars()["selectedlang"];
var appName = 'AppName';
var SUPPORTED_LANGS = ['en', 'hi', 'kn', 'fr', 'gu', 'te', 'as', 'ar', 'or', 'mr', 'bn', 'ta', 'ur', 'pt', 'pa'];

if (getUrlVars()["appname"]) {
    appName = getUrlVars()["appname"];
}

console.log('selected Lang', selectedLang);
$(document).ready(function () {

    window.addEventListener('message', function (event) {
        // This widget is embedded (e.g. via iframe) on arbitrary customer
        // domains that aren't known ahead of time, so a fixed origin
        // allowlist can't be hardcoded here. Instead, verify the message
        // actually came from the immediate parent window (not some other
        // frame/window) and that the payload has the expected shape before
        // trusting any of it.
        if (event.source !== window.parent) {
            return;
        }
        if (event.data && typeof event.data.appName === 'string') {
            appName = event.data.appName;
        }
    }, false);

    var jsonUrl;
    var normalizedLang = selectedLang ? selectedLang.trim().toLowerCase() : '';
    if (normalizedLang && SUPPORTED_LANGS.indexOf(normalizedLang) !== -1) {
        window.faqSelectedLang = normalizedLang;
        jsonUrl = "./resources/res/faq-" + window.faqSelectedLang + ".json"
    } else {
        jsonUrl = "./resources/res/faq-en.json"
    }

    console.log(jsonUrl);

    if (appName === 'AppName') {
        setTimeout(function () {
            readJson(jsonUrl);
        }, 100)
    } else {
        readJson(jsonUrl);
    }
});

function readJson(jsonUrl) {
    $.getJSON(jsonUrl, function (data) {
        for (var i = 0; i < data.faqs.length; i++) {
            if (data.faqs[i].topic.includes('{{APP_NAME}}')) {
                data.faqs[i].topic = data.faqs[i].topic.replace('{{APP_NAME}}', appName);
            }
            if (data.faqs[i].description.includes('{{APP_NAME}}')) {
                data.faqs[i].description = data.faqs[i].description.replace('{{APP_NAME}}', appName);
            }
        }

        var dir = selectedLang === 'ur' ? 'rtl' : 'ltr';

        var headerDiv = document.createElement('div');
        headerDiv.className = 'help-header';
        headerDiv.setAttribute('dir', dir);
        var headerTitle = document.createElement('h4');
        headerTitle.textContent = data.constants.help;
        var headerMsg = document.createElement('p');
        headerMsg.textContent = data.constants.faqMsg;
        headerDiv.appendChild(headerTitle);
        headerDiv.appendChild(headerMsg);

        var infoDiv = document.createElement('div');
        infoDiv.className = 'info-msg';
        infoDiv.setAttribute('dir', dir);
        var infoMsg = document.createElement('p');
        infoMsg.textContent = data.constants.resolveMsg;
        infoDiv.appendChild(infoMsg);

        $('#header').replaceWith(headerDiv);
        $(headerDiv).after(infoDiv);

        var accordionFragment = document.createDocumentFragment();
        $.each(data.faqs, function (key, value) {
            var panel = document.createElement('div');
            panel.className = 'panel panel-default';

            var panelToggle = document.createElement('div');
            panelToggle.setAttribute('data-toggle', 'collapse');
            panelToggle.setAttribute('data-parent', '#accordion');
            panelToggle.setAttribute('href', '#collapse' + key);

            var panelHeading = document.createElement('div');
            panelHeading.className = 'panel-heading';

            var panelTitle = document.createElement('div');
            panelTitle.className = 'panel-title';
            panelTitle.appendChild(document.createTextNode(value.topic));
            var arrowImg = document.createElement('img');
            arrowImg.src = './resources/images/Arrow.png';
            arrowImg.className = 'btn-arrow';
            panelTitle.appendChild(arrowImg);

            panelHeading.appendChild(panelTitle);
            panelToggle.appendChild(panelHeading);
            panel.appendChild(panelToggle);

            var panelCollapse = document.createElement('div');
            panelCollapse.id = 'collapse' + key;
            panelCollapse.className = 'panel-collapse collapse';

            var panelBody = document.createElement('div');
            panelBody.className = 'panel-body';
            var panelBodyText = document.createElement('p');
            panelBodyText.textContent = value.description;
            panelBody.appendChild(panelBodyText);

            var panelInteract = document.createElement('div');
            panelInteract.className = 'panel-interact';
            var interactMsg = document.createElement('p');
            interactMsg.textContent = data.constants.helpMsg;
            var btnNo = document.createElement('button');
            btnNo.type = 'button';
            btnNo.className = 'btn';
            btnNo.id = 'btn-no';
            btnNo.textContent = data.constants.noMsg;
            var btnYes = document.createElement('button');
            btnYes.type = 'button';
            btnYes.className = 'btn';
            btnYes.style.color = '#008840';
            btnYes.id = 'btn-yes';
            btnYes.textContent = data.constants.yesMsg;
            var yesClicked = document.createElement('p');
            yesClicked.className = 'yes-clicked';
            yesClicked.hidden = true;
            yesClicked.textContent = data.constants.thanksMsg;
            panelInteract.appendChild(interactMsg);
            panelInteract.appendChild(btnNo);
            panelInteract.appendChild(btnYes);
            panelInteract.appendChild(yesClicked);

            var panelInfo = document.createElement('div');
            panelInfo.className = 'panel-info';
            panelInfo.hidden = true;
            var sorryMsg = document.createElement('h6');
            sorryMsg.textContent = data.constants.sorryMsg;
            var knowMoreMsg = document.createElement('p');
            knowMoreMsg.textContent = data.constants.knowMoreMsg;
            var knowMoreForm = document.createElement('form');
            knowMoreForm.setAttribute('action', '#');
            knowMoreForm.id = 'know-more-form';
            knowMoreForm.className = 'know-more-form';
            var knowMoreTextarea = document.createElement('textarea');
            knowMoreTextarea.setAttribute('type', 'text');
            knowMoreTextarea.name = 'moreInfo';
            knowMoreTextarea.placeholder = data.constants.typeHere;
            knowMoreTextarea.className = 'input-text';
            knowMoreTextarea.maxLength = 1000;
            var knowMoreSubmit = document.createElement('input');
            knowMoreSubmit.type = 'submit';
            knowMoreSubmit.value = data.constants.submitButton;
            knowMoreSubmit.className = 'submit-button';
            knowMoreForm.appendChild(knowMoreTextarea);
            knowMoreForm.appendChild(knowMoreSubmit);
            var noClicked = document.createElement('p');
            noClicked.className = 'no-clicked';
            noClicked.hidden = true;
            noClicked.textContent = data.constants.thanksMsg;

            panelInfo.appendChild(sorryMsg);
            panelInfo.appendChild(knowMoreMsg);
            panelInfo.appendChild(knowMoreForm);
            panelInfo.appendChild(noClicked);

            panelCollapse.appendChild(panelBody);
            panelCollapse.appendChild(panelInteract);
            panelCollapse.appendChild(panelInfo);
            panel.appendChild(panelCollapse);

            accordionFragment.appendChild(panel);
        });
        $('#accordion').empty().append(accordionFragment);

        var sendEmailDiv = document.createElement('div');
        sendEmailDiv.className = 'send-email';
        var reportBtn = document.createElement('button');
        reportBtn.className = 'report-button';
        var reportImg = document.createElement('img');
        reportImg.src = './resources/images/Report.png';
        reportBtn.appendChild(reportImg);
        reportBtn.appendChild(document.createTextNode(' ' + data.constants.reportIssueMsg));
        sendEmailDiv.appendChild(reportBtn);
        $('#send-email').replaceWith(sendEmailDiv);
    });
}
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
