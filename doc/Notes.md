## OnBill App notes.

### Brief files description.

cb_onbill_carriers.erl:
- edit cariers docs;
- carriers docs intended to store carriers variables used upon documents generating, plus templates for these docs.

cb_onbill_variables.erl:
- read/edit onbill account's/reseller's variables used for monthly documents generating;
- this data located in "_id": "onbill" doc.

cb_onbills.erl:
- access to modb onbill data and different actions like generate docs, etc

cb_onbill_service_plans.erl:
- edit service_plan doc, because I just didn't found this functionality in stock cb_service_plans.erl

cb_onbill_transactions.erl:
- retrieve transactions information over API, as an example you could check/correct what was charged in daily-fee of a particular day

cb_periodic_fees.erl:
- manage periodic fees, like monthly fees, start and end date could be configured

kz_bookkeeper_onbill.erl:
- OnBill bookkeeper

kz_service_periodic_fees.erl:
- calculates periodic fees usage

onbill_daily_sync.erl:
- daily crawler intended to count daily fee at least once per day
 
