require 'ipaddress'
require 'aws-sdk'
require 'active_support'
require 'active_support/core_ext'
require 'active_support/inflector'
require 'active_support/inflector/inflections'
require 'enscalator/version'
require 'enscalator/helpers'
require 'enscalator/en_japan_configuration'
require 'enscalator/route53'
require 'enscalator/richtemplate'
require 'enscalator/enapp'
require 'enscalator/plugins/core_os'
require 'enscalator/plugins/elb'
require 'enscalator/plugins/couchbase'
require 'enscalator/plugins/core_os'
require 'enscalator/plugins/elasticsearch'
require 'enscalator/plugins/ubuntu'
require 'enscalator/plugins/rethinkdb'
require 'enscalator/plugins/rds'
require 'enscalator/plugins/rds_snapshot'
require 'enscalator/templates/enjapan_vpc'
require 'enscalator/templates/vpn'
require 'enscalator/templates/jobposting_storage'
require 'enscalator/templates/interaction'
require 'enscalator/templates/auth_service'
require 'enscalator/templates/enslurp'
require 'enscalator/templates/cc_rds'
require 'enscalator/templates/test_instance'

# Namespace for Enscalator related code
module Enscalator
end
