async = require 'async'
_ = require 'underscore'

mAccount = require './model/account'
mBalance = require './model/balance_log'

config = require '../config'

exports.cyclicalBilling = (callback) ->
  mAccount.find
    'billing.plans.0':
      $exists: true
  .toArray (err, accounts) ->
    async.each accounts, (account, callback) ->
      exports.triggerBilling account, ->
        callback()
    , ->
      callback()

exports.run = ->
  exports.cyclicalBilling ->
    setInterval ->
      exports.cyclicalBilling ->
    , config.billing.billing_cycle

# @param callback(account)
exports.triggerBilling = (account, callback) ->
  forceLeaveAllPlans = (callback) ->
    async.eachSeries account.billing.plans, (plan_name, callback) ->
      exports.leavePlan account, plan_name, callback
    , ->
      mAccount.findOne {_id: account._id}, (err, account) ->
        callback account

  is_force = do ->
    if account.billing.balance < config.billing.force_freeze.when_balance_below
      return true

    force_freeze_when = account.billing.arrears_at.getTime() + config.billing.force_freeze.when_arrears_above

    if account.billing.arrears_at and Date.now() > force_freeze_when
      return true

    return false

  async.each account.billing.plans, (plan_name, callback) ->
    exports.generateBilling account, plan_name, (result) ->
      callback null, result

  , (err, result) ->
    result = _.compact result

    if _.isEmpty result
      return callback account

    modifier =
      $set: {}
      $inc:
        'billing.balance': 0

    for item in result
      modifier.$set["billing.last_billing_at.#{item.name}"] = item.last_billing_at
      modifier.$inc['billing.balance'] += item.amount_inc

    if account.billing.balance > 0
      if account.billing.arrears_at
        modifier.$set['billing.arrears_at'] = null
    else if account.billing.balance < 0
      unless account.billing.arrears_at
        modifier.$set['billing.arrears_at'] = new Date()

    mAccount.findAndModify {_id: account._id}, null, modifier, {new: true}, (err, account) ->
      mBalance.create account, 'billing', modifier.$inc['billing.balance'],
        plans: _.indexBy result, 'name'
      , ->
        if is_force
          return forceLeaveAllPlans callback
        else
          callback account

exports.generateBilling = (account, plan_name, callback) ->
  plan_info = config.plans[plan_name]

  unless plan_info.billing_by_time
    return callback()

  last_billing_at = account.billing.last_billing_at[plan_name]

  unless last_billing_at < new Date()
    return callback()

  billing_time_range = (last_billing_at.getTime() + plan_info.billing_by_time.min_billing_unit) - Date.now()
  billing_unit_count = Math.floor billing_time_range / plan_info.billing_by_time.unit

  new_last_billing_at = new Date last_billing_at.getTime() + billing_unit_count * plan_info.billing_by_time.unit
  amount = billing_unit_count * plan_info.billing_by_time.price

  callback
    name: plan_name
    billing_unit_count: billing_unit_count
    last_billing_at: new_last_billing_at
    amount_inc: -amount

exports.joinPlan = (account, plan_name, callback) ->
  original_account = account
  plan_info = config.plans[plan_name]

  modifier =
    $addToSet:
      'billing.plans': plan_name
      'billing.services':
        $each: plan_info.services
    $set:
      'resources_limit': exports.calcResourcesLimit _.union account.billing.plans, [plan_name]

  for service_name in plan_info.services
    modifier.$set["billing.last_billing_at.#{service_name}"] = new Date()

  mAccount.findAndModify {_id: account._id}, modifier, {},
    new: true
  , (err, account) ->
    async.series _.difference(account.billing.services, original_account.billing.services), (service_name, callback) ->
      async.series pluggable.selectHook(account, "service.#{service_name}.enable"), (hook, callback) ->
        hook.action account, callback
      , callback
    , ->
      callback()

exports.leavePlan = (account, plan_name, callback) ->
  leaved_services = _.reject account.billing.services, (service_name) ->
    for item in _.without(account.billing.plans, plan_name)
      if service_name in config.plans[plan_name].services
        return true

    return false

  modifier =
    $pull:
      'billing.plans': plan_name
    $pullAll:
      'billing.services': leaved_services
    $set:
      'resources_limit': exports.calcResourcesLimit _.without account.billing.plans, plan_name
    $unset: {}

  for service_name in leaved_services
    modifier.$unset["billing.last_billing_at.#{service_name}"] = true

  mAccount.findAndModify {_id: account._id}, modifier, {},
    new: true
  , (err, account) ->
    async.series leaved_services, (service_name, callback) ->
      async.series pluggable.selectHook(account, "service.#{service_name}.disable"), (hook, callback) ->
        hook.action account, callback
      , callback
    , ->
      callback()

exports.calcResourcesLimit = (plans) ->
  limit = {}

  for plan_name in plans
    if config.plans[plan_name].resources
      for k, v of config.plans[plan_name].resources
        limit[k] ?= 0
        limit[k] += v

  return limit
