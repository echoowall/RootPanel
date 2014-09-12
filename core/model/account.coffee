nodemailer = require 'nodemailer'

{config, pluggable, utils} = app

mBalance = require './balance_log'

module.exports = exports = app.db.collection 'accounts'

sample =
  username: 'jysperm'
  password: '53673f434686ce045477f066f30eded55a9bb535a6cec7b73a60972ccafddb2a'
  password_salt: '53673f434686b535a6cec7b73a60ce045477f066f30eded55a9b972ccafddb2a'
  email: 'jysperm@gmail.com'
  created_at: Date()

  groups: ['root']

  settings:
    avatar_url: 'http://ruby-china.org/avatar/efcc15b92617a95a09f514a9bff9e6c3?s=58'
    language: 'zh_CN'
    timezone: 'Asia/Shanghai'
    QQ: '184300584'

  billing:
    services: ['shadowsocks']
    plans: ['all']

    last_billing_at:
      all: new Date()

    balance: 100
    arrears_at: new Date()

  pluggable:
    bitcoin:
      bitcoin_deposit_address: '13v2BTCMZMHg5v87susgg86HFZqXERuwUd'
      bitcoin_secret: '53673f434686b535a6cec7b73a60ce045477f066f30eded55a9b972ccafddb2a'

    phpfpm:
      is_enbale: false

    nginx:
      sites: []

  resources_limit:
    cpu: 144
    storage: 520
    transfer: 39
    memory: 27

  tokens: [
    type: 'access_token'
    token: 'b535a6cec7b73a60c53673f434686e04972ccafddb2a5477f066f30eded55a9b'
    is_available: true
    created_at: Date()
    updated_at: Date()
    payload:
      ip: '123.184.237.163'
      ua: 'Mozilla/5.0 (Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1700.102'
  ]

# @param account: username, email, password
# @param callback(account)
exports.register = (account, callback) ->
  password_salt = utils.randomSalt()

  {username, email, password} = account

  account =
    username: username
    password: utils.hashPassword(password, password_salt)
    password_salt: password_salt
    email: email
    created_at: new Date()

    group: []

    settings:
      avatar_url: "//ruby-china.org/avatar/#{utils.md5(email)}?s=58"
      language: config.i18n.default_language
      timezone: config.i18n.default_timezone

    billing:
      services: []
      plans: []

      balance: 0
      last_billing_at: {}
      arrears_at: null

    pluggable: {}

    resources_limit: {}

    tokens: []

  async.each pluggable.hooks.account.before_register, (hook_callback, callback) ->
    hook_callback account, callback
  , ->
    exports.insert account, (err, result) ->
      callback _.first result

exports.updatePassword = (account, password, callback) ->
  password_salt = utils.randomSalt()

  exports.update {_id: account._id},
    $set:
      password: utils.hashPassword password, password_salt
      password_salt: password_salt
  , callback

exports.byUsernameOrEmailOrId = (username, callback) ->
  exports.byUsername username, (err, account) ->
    if account
      return callback null, account

    exports.byEmail username, (err, account) ->
      if account
        return callback null, account

      exports.findId username, (err, account) ->
        callback null, account

exports.matchPassword = (account, password) ->
  return exports.hashPassword(password, account.password_salt) == account.password

exports.joinPlan = (account, plan, callback) ->
  account.attribute.plans.push plan
  exports.update {_id: account._id},
    $addToSet:
      'attribute.plans': plan
    $set:
      'attribute.resources_limit': exports.calcResourcesLimit account.attribute.plans
  , callback

exports.leavePlan = (account, plan, callback) ->
  account.attribute.plans = _.reject account.attribute.plans, (i) -> i == plan
  exports.update {_id: account._id},
    $pull:
      'attribute.plans': plan
    $set:
      'attribute.resources_limit': exports.calcResourcesLimit account.attribute.plans
  , callback

exports.incBalance = (account, type, amount, attribute, callback) ->
  exports.update {_id: account._id},
    $inc:
      'attribute.balance': amount
  , ->
    mBalance.create account, type, amount, attribute, (err, balance_log) ->
      callback balance_log
