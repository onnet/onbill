-module(onbill_notifications).

-export([send_account_update/1
        ,maybe_send_account_updates/2
        ,mrc_approaching_sent/1, set_mrc_approaching_sent/1, reset_mrc_approaching_sent/1
        ,mrc_approaching_enabled/1, set_mrc_approaching_enabled/1, reset_mrc_approaching_enabled/1
        ,mrc_approaching_tstamp/1, set_mrc_approaching_tstamp/1, remove_mrc_approaching_tstamp/1
        ,mrc_approaching_enabled_exists/1
        ]).

-include("onbill.hrl").

-define(MRC_APPROACHING_SENT, [<<"notifications">>, <<"mrc_approaching">>, <<"sent_mrc_approaching">>]).
-define(MRC_APPROACHING_ENABLED, [<<"notifications">>, <<"mrc_approaching">>, <<"enabled">>]).
-define(MRC_APPROACHING_TSTAMP, [<<"notifications">>, <<"mrc_approaching">>, <<"last_notification">>]).
-define(MRC_APPROACHING_REPEAT,
        kapps_config:get_integer(?MOD_CONFIG_CRAWLER, <<"mrc_approaching_repeat_s">>, 1 * ?SECONDS_IN_DAY)).


-spec send_account_update(ne_binary()) -> 'ok'.
send_account_update(AccountId) ->
    case kz_amqp_worker:call(build_customer_update_payload(AccountId)
                            ,fun kapi_notifications:publish_customer_update/1
                            ,fun kapi_notifications:customer_update_v/1
                            )
    of
        {'ok', _Resp} ->
            lager:debug("published customer_update notification");
        {'error', _E} ->
            lager:debug("failed to publish_customer update notification: ~p", [_E])
    end.

-spec build_customer_update_payload(cb_context:context()) -> kz_proplist().
build_customer_update_payload(AccountId) ->
  {'ok', AccountDoc} = kz_account:fetch(AccountId),
    props:filter_empty(
      [{<<"Account-ID">>, kz_services:find_reseller_id(AccountId)}
   %   ,{<<"Recipient-ID">>, AccountId}
      ,{<<"Recipient-ID">>, <<"9dab2e56e27b4d1ce381ca9aaa8b0303">>}
      ,{<<"Template-ID">>, <<"customer_update_billing_period">>}
      ,{<<"DataBag">>, {[{<<"field1">>,<<"value1">>},{<<"field2">>,{[{<<"subfield1">>,kz_account:name(AccountDoc)},{<<"subfield2">>,<<"subvalue2">>}]}}]}}
      ,{<<"HTML">>, base64:encode(<<"Dear {{user.first_name}} {{user.last_name}}. <br /><br />DataBag test: {{databag.field2.subfield1}} <br /><br /> Kind regards,">>)}
      ,{<<"Text">>, <<"Oh Dear {{user.first_name}} {{user.last_name}}.\n\nDataBag test: {{databag.field2.subfield2}}\n\nBest regards,">>}
       | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
      ]).

-spec maybe_send_account_updates(ne_binary(), kz_account:doc()) -> 'ok'.
maybe_send_account_updates(AccountId, AccountJObj) ->
    case onbill_util:maybe_allow_postpay(AccountId) of
        'true' -> 'ok';
        'false' ->
            maybe_new_billing_period_approaching(AccountId, AccountJObj)
    end.

-spec maybe_new_billing_period_approaching(ne_binary(), kz_account:doc()) -> 'ok'.
maybe_new_billing_period_approaching(AccountId, AccountJObj) ->
    Timestamp = kz_time:current_tstamp(),
    {StartYear, StartMonth, StartDay} = onbill_util:period_start_date(AccountId, Timestamp),
    case onbill_util:days_left_in_period(StartYear, StartMonth, StartDay, Timestamp) of
        DaysLeft when DaysLeft < 5 ->
            case onbill_bk_util:current_usage_amount_in_units(AccountId)
                > wht_util:current_balance(AccountId) * 0.9
            of
                'true' ->
                    maybe_send_new_billing_period_approaching_update(AccountId, AccountJObj, mrc_approaching_enabled(AccountJObj));
                _ -> 'ok'
            end;
        _ -> 'ok'
    end.

-spec maybe_send_new_billing_period_approaching_update(ne_binary(), kz_account:doc(), boolean()) -> 'ok'.
maybe_send_new_billing_period_approaching_update(AccountId, AccountJObj, 'true') ->
    case mrc_approaching_tstamp(AccountJObj) of
        MRC_ApproachingSent when is_number(MRC_ApproachingSent) ->
            Cycle = ?MRC_APPROACHING_REPEAT,
            Diff = kz_time:current_tstamp() - MRC_ApproachingSent,
            case Diff >= Cycle of
               'true' ->
                    'ok' = send_account_update(AccountId),
                    update_account_mrc_approaching_sent(AccountJObj);
               'false' ->
                   lager:debug("mrc approaching alert sent ~w seconds ago, repeats every ~w", [Diff, Cycle])
            end;
        _Else ->
            'ok' = send_account_update(AccountId),
            update_account_mrc_approaching_sent(AccountJObj)
    end,
    'ok';
maybe_send_new_billing_period_approaching_update(AccountId, _AccountJObj, 'false') ->
    lager:debug("mrc approaching alert disabled for Account: ~p", [AccountId]).

-spec update_account_mrc_approaching_sent(kz_account:doc()) -> 'ok'.
update_account_mrc_approaching_sent(AccountJObj0) ->
    AccountJObj1 = set_mrc_approaching_sent(AccountJObj0),
    AccountJObj2 = set_mrc_approaching_tstamp(AccountJObj1),
    _ = kz_util:account_update(AccountJObj2),
   'ok'.

-spec mrc_approaching_sent(kz_account:doc()) -> boolean().
mrc_approaching_sent(JObj) ->
    kz_json:is_true(?MRC_APPROACHING_SENT, JObj).

-spec set_mrc_approaching_sent(kz_account:doc()) -> kz_account:doc().
set_mrc_approaching_sent(JObj) ->
    kz_json:set_value(?MRC_APPROACHING_SENT, 'true', JObj).

-spec reset_mrc_approaching_sent(kz_account:doc()) -> kz_account:doc().
reset_mrc_approaching_sent(JObj) ->
    kz_json:set_value(?MRC_APPROACHING_SENT, 'false', JObj).

-spec mrc_approaching_enabled(kz_account:doc()) -> boolean().
mrc_approaching_enabled(JObj) ->
    kz_json:is_true(?MRC_APPROACHING_ENABLED, JObj, 'true').

-spec set_mrc_approaching_enabled(kz_account:doc()) -> kz_account:doc().
set_mrc_approaching_enabled(JObj) ->
    kz_json:set_value(?MRC_APPROACHING_ENABLED, 'true', JObj).

-spec reset_mrc_approaching_enabled(kz_account:doc()) -> kz_account:doc().
reset_mrc_approaching_enabled(JObj) ->
    kz_json:set_value(?MRC_APPROACHING_ENABLED, 'false', JObj).

-spec mrc_approaching_enabled_exists(kz_account:doc()) -> boolean().
mrc_approaching_enabled_exists(JObj) ->
    kz_json:get_ne_value(?MRC_APPROACHING_ENABLED, JObj) =/= 'undefined'.

-spec mrc_approaching_tstamp(kz_account:doc()) -> api_number().
mrc_approaching_tstamp(JObj) ->
    kz_json:get_integer_value(?MRC_APPROACHING_TSTAMP, JObj).

-spec set_mrc_approaching_tstamp(kz_account:doc()) -> kz_account:doc().
set_mrc_approaching_tstamp(JObj) ->
    TStamp = kz_time:current_tstamp(),
    set_mrc_approaching_tstamp(JObj, TStamp).

-spec set_mrc_approaching_tstamp(kz_account:doc(), number()) -> kz_account:doc().
set_mrc_approaching_tstamp(JObj, TStamp) ->
    kz_json:set_value(?MRC_APPROACHING_TSTAMP, TStamp, JObj).

-spec remove_mrc_approaching_tstamp(kz_account:doc()) -> kz_account:doc().
remove_mrc_approaching_tstamp(JObj) ->
    kz_json:delete_key(?MRC_APPROACHING_TSTAMP, JObj).

