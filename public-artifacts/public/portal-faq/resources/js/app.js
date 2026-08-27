$(document).ready(function(){
    // This FAQ widget is embedded (e.g. via iframe) on arbitrary customer
    // domains that aren't known at build time, so a single hardcoded
    // postMessage target origin can't be baked in here. When available,
    // derive the parent's origin from document.referrer (set by the browser
    // to the embedding page's URL) so messages stay scoped to the actual
    // parent instead of any listener on the page. If no referrer is
    // available (e.g. a Referrer-Policy strips it, or the page isn't
    // framed), fall back to '*' explicitly and intentionally.
    var targetOrigin = '*';
    if (document.referrer) {
        try {
            var referrerLink = document.createElement('a');
            referrerLink.href = document.referrer;
            if (referrerLink.protocol && referrerLink.host) {
                targetOrigin = referrerLink.protocol + '//' + referrerLink.host;
            }
        } catch (e) {
            targetOrigin = '*';
        }
    }

    // Toggle plus minus icon on show hide of collapse element
     $(document).on('show.bs.collapse', ".collapse", function() {
        $(this).parent().find(".btn-arrow").addClass("rotate");
        $(this).parent().find(".panel-title").css({"color":"#024F9D"})

    }).on('hide.bs.collapse', ".collapse", function() {
        $(this).parent().find(".btn-arrow").removeClass("rotate");
        $(this).parent().find(".panel-title").css({"color":"inherit"});
    });

    $(document).on( 'click','[id="btn-yes"]',function(){
        var value = {};
        console.log("Yes-Clicked");
        value.action = "yes-clicked"
        value.position = Number($(this).parent().parent().attr("id").substr(-1)) +1;
        value.value = {};
        value.value.topic = $(this).parent().parent().parent().find(".panel-title").first().text().trim();
        value.value.description = $(this).parent().parent().find("p").first().text();

        window.parent.postMessage(value, targetOrigin);
        $(this).parent().find('button').hide();
        $(this).parent().find("p").first().hide();
        $(this).parent().children().last().removeAttr('hidden');

    })

    $(document).on( 'click','[id="btn-no"]',function(){
        console.log("No-Clicked");
        var value = {};
        value.action = "no-clicked"
        value.position = Number($(this).parent().parent().attr("id").substr(-1)) +1;
        value.value = {};
        value.value.topic = $(this).parent().parent().parent().find(".panel-title").first().text().trim();
        value.value.description = $(this).parent().parent().find("p").first().text();

        window.parent.postMessage(value, targetOrigin);
        $(this).parent().hide();
        $(this).parent().parent().find('.panel-info').removeAttr('hidden');
    })

    $(document).on( 'keypress','.input-text',function() {
        if($(this).val().length > 999) {
            //display your warinig the way you chose
            console.log('MaxLength Reached');
        }
    });
    $(document).on( 'submit','#know-more-form',function(e) {
        e.preventDefault();
        var inputVal = $( this )[0][0].value; // resolves to current input element.
        if(inputVal && inputVal.length){
            var value = {};
            value.action = "no-clicked"
            value.position = Number($(this).parent().parent().attr("id").substr(-1)) +1;
            value.value = {};
            value.value.topic = $(this).parent().parent().parent().find(".panel-title").first().text().trim();
            value.value.description = $(this).parent().parent().find("p").first().text();
            value.value.knowMoreText=inputVal;
            window.parent.postMessage(value, targetOrigin);

        }
        $(this).parent().children().last().removeAttr('hidden');
        $(this).parent().css("padding", "20px");
        $(this).parent().css("height", "100px");
        $(this).parent().children().last().removeAttr('hidden');
        $(this).parent().children().not('.no-clicked').hide();


    });
    $(document).on('click', '.send-email', function(){
        var value = {};
        value.action = "report-other-issues-clicked";
        window.parent.postMessage(value, targetOrigin);

        if(window.selectedLang){
            window.location.href = "reportIssue.html?selectedlang="+window.selectedLang;
        } else{
            window.location.href = "reportIssue.html"
        }
        console.log(window.faqSelectedLang);
    });

    $(document).on( 'submit','#send-email-form',function(e) {
        e.preventDefault();
        $(this).removeClass('selected');
        var inputVal = $( this )[0][0].value; // resolves to current input element.
            var value = {};
            value.action = "initiate-email-clicked";
            value.value = {};
            value.initiateEmailBody=inputVal;
            window.parent.postMessage(value, targetOrigin);
    });
    $(document).on( 'keyup','.input-text-form',function() {
        var maxLength = 1000;
        var length = $(this).val().length;
        var length = maxLength-length;
        $('#charleft').text(length);
    });
});
