--   Copyright © 2011 Hedera Technology SAS
--   This program is free software: you can redistribute it and/or modify
--   it under the terms of the GNU Affero General Public License as
--   published by the Free Software Foundation, either version 3 of the
--   License, or (at your option) any later version.
--
--   This program is distributed in the hope that it will be useful,
--   but WITHOUT ANY WARRANTY; without even the implied warranty of
--   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--   GNU Affero General Public License for more details.
--
--   You should have received a copy of the GNU Affero General Public License
--   along with this program.  If not, see <http://www.gnu.org/licenses/>.

DROP DATABASE IF EXISTS `administrator`;

CREATE DATABASE `administrator`;
USE `administrator`;

SET foreign_key_checks=0;

--
-- Table structure for table `kernel`
--

CREATE TABLE `kernel` (
  `kernel_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `kernel_name` char(64) NOT NULL,
  `kernel_version` char(32) NOT NULL,
  `kernel_desc` char(255) DEFAULT NULL,
  PRIMARY KEY (`kernel_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `processormodel`
--

CREATE TABLE `processormodel` (
  `processormodel_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `processormodel_brand` char(64) NOT NULL,
  `processormodel_name` char(32) NOT NULL,
  `processormodel_core_num` int(2) unsigned NOT NULL,
  `processormodel_clock_speed` float unsigned NOT NULL,
  `processormodel_l2_cache` int(2) unsigned NOT NULL,
  `processormodel_max_tdp` int(2) unsigned NOT NULL,
  `processormodel_64bits` int(1) unsigned NOT NULL,
  `processormodel_virtsupport` int(1) unsigned NOT NULL,
  PRIMARY KEY (`processormodel_id`),
  UNIQUE KEY `processormodel_name_UNIQUE` (`processormodel_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `powersupplycardmodel`
--

CREATE TABLE `powersupplycardmodel` (
  `powersupplycardmodel_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `powersupplycardmodel_brand` char(64) NOT NULL,
  `powersupplycardmodel_name` char(32) NOT NULL,
  `powersupplycardmodel_slotscount` int(2) unsigned NOT NULL,
  PRIMARY KEY (`powersupplycardmodel_id`),
  UNIQUE KEY `powersupplycardmodel_name_UNIQUE` (`powersupplycardmodel_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `hostmodel`
--

CREATE TABLE `hostmodel` (
  `hostmodel_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `hostmodel_brand` char(64) NOT NULL,
  `hostmodel_name` char(32) NOT NULL,
  `hostmodel_chipset` char(64) NOT NULL,
  `hostmodel_processor_num` int(1) unsigned NOT NULL,
  `hostmodel_consumption` int(2) unsigned NOT NULL,
  `hostmodel_iface_num` int(1) unsigned NOT NULL,
  `hostmodel_ram_slot_num` int(1) unsigned NOT NULL,
  `hostmodel_ram_max` int(1) unsigned NOT NULL,
  `processormodel_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`hostmodel_id`),
  UNIQUE KEY `hostmodel_name_UNIQUE` (`hostmodel_name`),
  KEY `fk_hostmodel_1` (`processormodel_id`),
  CONSTRAINT `fk_hostmodel_1` FOREIGN KEY (`processormodel_id`) REFERENCES `processormodel` (`processormodel_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



--
-- Table structure for table `harddisk`
--
CREATE TABLE `harddisk` (
  `harddisk_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `host_id` int(8) unsigned NOT NULL,
  `harddisk_device` char(32) NOT NULL,
  PRIMARY KEY (`harddisk_id`),
  KEY `fk_harddisk_1` (`host_id`),
  CONSTRAINT `fk_harddisk_1` FOREIGN KEY (`host_id`) REFERENCES `host` (`host_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `host`
--

CREATE TABLE `host` (
  `host_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `hostmodel_id` int(8) unsigned NULL DEFAULT NULL,
  `processormodel_id` int(8) unsigned NULL DEFAULT NULL,
  `kernel_id` int(8) unsigned NOT NULL,
  `host_serial_number` char(64) NOT NULL,
  `host_powersupply_id` int(8) unsigned,
  `host_ipv4_internal_id` int(8) unsigned  DEFAULT NULL,
  `host_desc` char(255) DEFAULT NULL,
  `active` int(1) unsigned NOT NULL,
  `host_mac_address` char(18) NOT NULL,
  `host_initiatorname` char(64) DEFAULT NULL,
  `host_internal_ip` char(15) DEFAULT NULL,
  `host_ram` bigint unsigned DEFAULT NULL,
  `host_core` int(1) unsigned DEFAULT NULL,
  `host_hostname` char(32) DEFAULT NULL,
  `etc_device_id` int(8) unsigned DEFAULT NULL,
  `host_state` char(32) NOT NULL DEFAULT 'down',
  `host_prev_state` char(32),
  PRIMARY KEY (`host_id`),
  UNIQUE KEY `host_internal_ip_UNIQUE` (`host_internal_ip`),
  UNIQUE KEY `host_mac_address_UNIQUE` (`host_mac_address`),
  KEY `fk_host_1` (`hostmodel_id`),
  KEY `fk_host_2` (`processormodel_id`),
  KEY `fk_host_3` (`kernel_id`),
  KEY `fk_host_4` (`etc_device_id`),
  KEY `fk_host_5` (`host_powersupply_id`),
  KEY `fk_host_6` (`host_ipv4_internal_id`),
  CONSTRAINT `fk_host_1` FOREIGN KEY (`hostmodel_id`) REFERENCES `hostmodel` (`hostmodel_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_2` FOREIGN KEY (`processormodel_id`) REFERENCES `processormodel` (`processormodel_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_3` FOREIGN KEY (`kernel_id`) REFERENCES `kernel` (`kernel_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_4` FOREIGN KEY (`etc_device_id`) REFERENCES `lvm2_lv` (`lvm2_lv_id`) ON DELETE SET NULL ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_5` FOREIGN KEY (`host_powersupply_id`) REFERENCES `powersupply` (`powersupply_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_6` FOREIGN KEY (`host_ipv4_internal_id`) REFERENCES `ipv4_internal` (`ipv4_internal_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `hostdetails`
--

CREATE TABLE `hostdetails` (
  `host_id` int(8) unsigned NOT NULL,
  `name` char(32) NOT NULL,
  `value` char(255) DEFAULT NULL,
  PRIMARY KEY (`host_id`,`name`),
  KEY `fk_hostdetails_1` (`host_id`),
  CONSTRAINT `fk_hostdetails_1` FOREIGN KEY (`host_id`) REFERENCES `host` (`host_id`)  ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `powersupply`
--
CREATE TABLE `powersupply` (
  `powersupply_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `powersupplycard_id` int(8) unsigned NOT NULL,
  `powersupplyport_number` int(8) unsigned NOT NULL,
  PRIMARY KEY (`powersupply_id`),
  KEY `fk_powersupplycard_1` (`powersupplycard_id`),
  CONSTRAINT `fk_powersupplycard_1` FOREIGN KEY (`powersupplycard_id`) REFERENCES `powersupplycard` (`powersupplycard_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `powersupplycard`
--
CREATE TABLE `powersupplycard` (
  `powersupplycard_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `powersupplycard_name` char(64) NOT NULL,
  `ipv4_internal_id` int(8) unsigned DEFAULT NULL,
  `powersupplycardmodel_id` int(8) unsigned DEFAULT NULL,
  `powersupplycard_mac_address` char(32) NOT NULL,
  `active` int(1),
  PRIMARY KEY (`powersupplycard_id`),
  KEY `fk_powersupplycardmodel` (`powersupplycardmodel_id`),
  KEY `fk_powersupplycard_ipv4_internal_id` (`ipv4_internal_id`),
  CONSTRAINT `fk_powersupplycardmodel` FOREIGN KEY (`powersupplycardmodel_id`) REFERENCES `powersupplycardmodel` (`powersupplycardmodel_id`)  ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_powersupplycard_ipv4_internal_id` FOREIGN KEY (`ipv4_internal_id`) REFERENCES `ipv4_internal` (`ipv4_internal_id`)  ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `distribution`
--

CREATE TABLE `distribution` (
  `distribution_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `distribution_name` char(64) NOT NULL,
  `distribution_version` char(32) NOT NULL,
  `distribution_desc` char(255) DEFAULT NULL,
  `etc_device_id` int(8) unsigned DEFAULT NULL,
  `root_device_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`distribution_id`),
  KEY `fk_distribution_1` (`etc_device_id`),
  KEY `fk_distribution_2` (`root_device_id`),
  CONSTRAINT `fk_distribution_1` FOREIGN KEY (`etc_device_id`) REFERENCES `lvm2_lv` (`lvm2_lv_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_distribution_2` FOREIGN KEY (`root_device_id`) REFERENCES `lvm2_lv` (`lvm2_lv_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `cluster`
--

CREATE TABLE `cluster` (
  `cluster_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_name` char(32) NOT NULL,
  `cluster_desc` char(255) DEFAULT NULL,
  `cluster_type` int(1) unsigned DEFAULT NULL,
  `cluster_min_node` int(2) unsigned NOT NULL,
  `cluster_max_node` int(2) unsigned NOT NULL,
  `cluster_priority` int(1) unsigned NOT NULL,
  `cluster_si_location` ENUM('local','diskless') NOT NULL,
  `cluster_si_access_mode` ENUM('ro','rw') NOT NULL,
  `cluster_si_shared` int(1) unsigned NOT NULL,
  `cluster_domainname` char(64) NOT NULL,
  `cluster_nameserver` char(15) NOT NULL,
  `active` int(1) unsigned NOT NULL,
  `systemimage_id` int(8) unsigned DEFAULT NULL,
  `kernel_id` int(8) unsigned DEFAULT NULL,
  `cluster_state` char(32) NOT NULL DEFAULT 'down',
  `cluster_prev_state` char(32),
  PRIMARY KEY (`cluster_id`),
--  KEY `fk_cluster_1` (`infrastructure_id`),
  UNIQUE KEY `cluster_name_UNIQUE` (`cluster_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `clusterdetails`
--

CREATE TABLE `clusterdetails` (
  `cluster_id` int(8) unsigned NOT NULL,
  `name` char(32) NOT NULL,
  `value` char(255) NOT NULL,
  PRIMARY KEY (`cluster_id`,`name`),
  KEY `fk_clusterdetails_1` (`cluster_id`),
  CONSTRAINT `fk_clusterdetails_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `node`
--

CREATE TABLE `node` (
  `node_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_id` int(8) unsigned NOT NULL,
  `host_id` int(8) unsigned NOT NULL,
  `master_node` int(1) unsigned DEFAULT NULL,
  `node_state` char(32),
  `node_prev_state` char(32),
  PRIMARY KEY (`node_id`),
  UNIQUE `cluster_id` (`cluster_id`,`host_id`),
  UNIQUE `fk_node_2` (`host_id`),
  KEY `fk_node_1` (`cluster_id`),
  CONSTRAINT `fk_node_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_node_2` FOREIGN KEY (`host_id`) REFERENCES `host` (`host_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operationtype`
--

CREATE TABLE `operationtype` (
  `operationtype_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `operationtype_name` char(64) DEFAULT NULL,
  PRIMARY KEY (`operationtype_id`),
  UNIQUE KEY `operationtype_name_UNIQUE` (`operationtype_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operation`
--

CREATE TABLE `operation` (
  `operation_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `type` char(64) NOT NULL,
  `user_id` int(8) unsigned NOT NULL,
  `priority` int(2) unsigned NOT NULL,
  `creation_date` date NOT NULL,
  `creation_time` time NOT NULL,
  `hoped_execution_time` int(4) unsigned DEFAULT NULL,
  `execution_rank` int(8) unsigned NOT NULL,
  PRIMARY KEY (`operation_id`),
  UNIQUE KEY `execution_rank_UNIQUE` (`execution_rank`),
  KEY `fk_operation_queue_1` (`user_id`),
  KEY `fk_operation_queue_2` (`type`),
  CONSTRAINT `fk_operation_queue_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_operation_queue_2` FOREIGN KEY (`type`) REFERENCES `operationtype` (`operationtype_name`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operation_parameter`
--

CREATE TABLE `operation_parameter` (
  `operation_param_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `value` char(255) NOT NULL,
  `operation_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`operation_param_id`),
  KEY `fk_operation_parameter_1` (`operation_id`),
  CONSTRAINT `fk_operation_parameter_1` FOREIGN KEY (`operation_id`) REFERENCES `operation` (`operation_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `old_operation`
--

CREATE TABLE `old_operation` (
  `old_operation_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `type` char(64) NOT NULL,
  `user_id` int(8) unsigned NOT NULL,
  `priority` int(2) unsigned NOT NULL,
  `creation_date` date NOT NULL,
  `creation_time` time NOT NULL,
  `execution_date` date NOT NULL,
  `execution_time` time NOT NULL,
  `execution_status` char(32) NOT NULL,
  PRIMARY KEY (`old_operation_id`),
  KEY `fk_old_operation_queue_1` (`user_id`),
  KEY `fk_old_operation_queue_2` (`type`),
  CONSTRAINT `fk_old_operation_queue_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_old_operation_queue_2` FOREIGN KEY (`type`) REFERENCES `operationtype` (`operationtype_name`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operation_parameter`
--

CREATE TABLE `old_operation_parameter` (
  `old_operation_param_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `value` char(255) NOT NULL,
  `old_operation_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`old_operation_param_id`),
  KEY `fk_old_operation_parameter_1` (`old_operation_id`),
  CONSTRAINT `fk_old_operation_parameter_1` FOREIGN KEY (`old_operation_id`) REFERENCES `old_operation` (`old_operation_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `systemimage`
--

CREATE TABLE `systemimage` (
  `systemimage_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `systemimage_name` char(32) NOT NULL,
  `systemimage_desc` char(255) DEFAULT NULL,
  `systemimage_dedicated` int(1) unsigned NOT NULL DEFAULT 0,
  `distribution_id` int(8) unsigned NOT NULL,
  `etc_device_id` int(8) unsigned DEFAULT NULL,
  `root_device_id` int(8) unsigned DEFAULT NULL,
  `active` int(1) unsigned NOT NULL,
  PRIMARY KEY (`systemimage_id`),
  UNIQUE KEY `systemimage_name_UNIQUE` (`systemimage_name`),
  KEY `fk_systemimage_1` (`distribution_id`),
  KEY `fk_systemimage_2` (`etc_device_id`),
  KEY `fk_systemimage_3` (`root_device_id`),
  CONSTRAINT `fk_systemimage_1` FOREIGN KEY (`distribution_id`) REFERENCES `distribution` (`distribution_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_systemimage_2` FOREIGN KEY (`etc_device_id`) REFERENCES `lvm2_lv` (`lvm2_lv_id`) ON DELETE SET NULL ON UPDATE NO ACTION,
  CONSTRAINT `fk_systemimage_3` FOREIGN KEY (`root_device_id`) REFERENCES `lvm2_lv` (`lvm2_lv_id`) ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `ipv4_internal`
--

CREATE TABLE `ipv4_internal` (
  `ipv4_internal_id` int(8) UNSIGNED NOT NULL AUTO_INCREMENT ,
  `ipv4_internal_address` char(15) NOT NULL ,
  `ipv4_internal_mask` char(15) NOT NULL ,
  `ipv4_internal_default_gw` char(15) NULL ,
  PRIMARY KEY (`ipv4_internal_id`),
  UNIQUE KEY `ipv4_internal_address_UNIQUE` (`ipv4_internal_address`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `ipv4_dmz`
--

CREATE TABLE `ipv4_dmz` (
  `ipv4_dmz_id` int(8) UNSIGNED NOT NULL AUTO_INCREMENT ,
  `ipv4_dmz_address` char(15) NOT NULL ,
  `ipv4_dmz_mask` char(15) NOT NULL ,
  `tier_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`ipv4_dmz_id`),
  UNIQUE KEY `ipv4_dmz_address_UNIQUE` (`ipv4_dmz_address`),
  KEY `fk_ipv4_dmz_1` (`tier_id`),
  CONSTRAINT `fk_ipv4_dmz_1` FOREIGN KEY (`tier_id`) REFERENCES `tier` (`tier_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `ipv4_public`
--

CREATE TABLE `ipv4_public` (
  `ipv4_public_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `ipv4_public_address` char(15) NOT NULL,
  `ipv4_public_mask` char(15) NOT NULL,
  `ipv4_public_default_gw` char(15) DEFAULT NULL,
  `cluster_id` int(8) unsigned DEFAULT NULL,
  `infrastructure_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`ipv4_public_id`),
  KEY `fk_ipv4_public_1` (`cluster_id`),
  KEY `fk_ipv4_public_2` (`infrastructure_id`),
  CONSTRAINT `fk_ipv4_public_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE SET NULL ON UPDATE NO ACTION,
  CONSTRAINT `fk_ipv4_public_2` FOREIGN KEY (`infrastructure_id`) REFERENCES `infrastructure` (`infrastructure_id`) ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `ipv4_route`
--

CREATE TABLE `ipv4_route` (
  `ipv4_route_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `ipv4_route_destination` char(15) NOT NULL,
  `ipv4_route_gateway` char(15) DEFAULT NULL,
  `ipv4_route_context` char(10) NOT NULL, -- Context could be internal or public
  PRIMARY KEY (`ipv4_route_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `cluster_ipv4_route`
--

CREATE TABLE `cluster_ipv4_route` (
  `cluster_ipv4_route_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_id` int(8) unsigned NOT NULL,
  `ipv4_route_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`cluster_ipv4_route_id`),
  KEY `fk_cluster_ipv4_route_1` (`cluster_id`),
  KEY `fk_cluster_ipv4_route_2` (`ipv4_route_id`),
  UNIQUE KEY `index4` (`cluster_id`,`ipv4_route_id`),
  CONSTRAINT `fk_cluster_ipv4_route_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_cluster_ipv4_route_2` FOREIGN KEY (`ipv4_route_id`) REFERENCES `ipv4_route` (`ipv4_route_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `user`
--

CREATE TABLE `user` (
  `user_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `user_system` int(1) unsigned NOT NULL DEFAULT 0,
  `user_login` char(32) NOT NULL,
  `user_password` char(32) NOT NULL,
  `user_firstname` char(64) DEFAULT NULL,
  `user_lastname` char(64) DEFAULT NULL,
  `user_email` char(255) DEFAULT NULL,
  `user_creationdate` date DEFAULT NULL,
  `user_lastaccess` datetime DEFAULT NULL,
  `user_desc` char(255) DEFAULT 'Note concerning this user',
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `user_login` (`user_login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `gp`
--

CREATE TABLE `gp` (
  `gp_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `gp_name` char(32) NOT NULL,
  `gp_type` char(32) NOT NULL,
  `gp_desc` char(255) DEFAULT NULL,
  `gp_system` int(1) unsigned NOT NULL,
  PRIMARY KEY (`gp_id`),
  UNIQUE KEY `gp_name` (`gp_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `message`
--

CREATE TABLE `message` (
  `message_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(8) unsigned DEFAULT NULL,
  `message_from` char(32) NOT NULL,
  `message_creationdate` date NOT NULL,
  `message_creationtime` time NOT NULL,
  `message_level` char(32) NOT NULL,
  `message_content` text(512) NOT NULL,
  PRIMARY KEY (`message_id`),
  KEY `fk_message_1` (`user_id`),
  CONSTRAINT `fk_message_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Component management tables
--

--
-- Table structure for table `component`
--

CREATE TABLE `component` (
  `component_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `component_name` char(32) NOT NULL,
  `component_version` char(32) NOT NULL,
  `component_category` char(32) NOT NULL,
  PRIMARY KEY (`component_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_provided`
--

CREATE TABLE `component_provided` (
  `component_id` int(8) unsigned NOT NULL,
  `distribution_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`component_id`,`distribution_id`),
  KEY `fk_component_provided_1` (`component_id`),
  KEY `fk_component_provided_2` (`distribution_id`),
  CONSTRAINT `fk_component_provided_1` FOREIGN KEY (`component_id`) REFERENCES `component` (`component_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_provided_2` FOREIGN KEY (`distribution_id`) REFERENCES `distribution` (`distribution_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_installed`
--

CREATE TABLE `component_installed` (
  `component_id` int(8) unsigned NOT NULL,
  `systemimage_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`component_id`,`systemimage_id`),
  KEY `fk_component_installed_1` (`component_id`),
  KEY `fk_component_installed_2` (`systemimage_id`),
  CONSTRAINT `fk_component_installed_1` FOREIGN KEY (`component_id`) REFERENCES `component` (`component_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_installed_2` FOREIGN KEY (`systemimage_id`) REFERENCES `systemimage` (`systemimage_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for `infrastructure`
--

CREATE TABLE `infrastructure` (
  `infrastructure_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `infrastructure_reference` char(64) NOT NULL,
  `infrastructure_min_node` int(2) unsigned NOT NULL,
  `infrastructure_max_node` int(2) unsigned NOT NULL,
  `infrastructure_domainname` char(64) NOT NULL,
  `infrastructure_nameserver` char(15) NOT NULL,
  `infrastructure_name` char(32) NOT NULL,
  `infrastructure_desc` char(255) DEFAULT NULL,
  `infrastructure_version` char(32) NOT NULL,
  `infrastructure_tier_number` int(1),
  `infrastructure_state` char(32) NOT NULL DEFAULT 'down',
  `infrastructure_prev_state` char(32),
  `infrastructure_priority` int(1) unsigned NOT NULL,
  PRIMARY KEY (`infrastructure_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for `tier`
--
-- #TODO Warning Here delete tier when cluster removed by when cluster will be used by tier then they will not be destroyed when cluster are. 
CREATE TABLE `tier` (
  `tier_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `infrastructure_id` int(8) unsigned NOT NULL,
  `cluster_id` int(8) unsigned,
  `tier_name` char(32) NOT NULL,
  `tier_rank` int(1) NOT NULL,
  `tier_data_src` char(128) NOT NULL,
  `tier_poststart_script` char(64),
  PRIMARY KEY (`tier_id`),
  KEY `fk_tier_1` (`infrastructure_id`),
  KEY `fk_tier_2` (`cluster_id`),
  CONSTRAINT `fk_tier_1` FOREIGN KEY (`infrastructure_id`) REFERENCES `infrastructure` (`infrastructure_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_tier_2` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_instance`
--

CREATE TABLE `component_instance` (
  `component_instance_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_id` int(8) unsigned,
  `component_id` int(8) unsigned NOT NULL,
  `tier_id` int(8) unsigned,
  `component_template_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`component_instance_id`),
  KEY `fk_component_instance_1` (`cluster_id`),
  KEY `fk_component_instance_2` (`component_template_id`),
  KEY `fk_component_instance_3` (`component_id`),
  KEY `fk_component_instance_4` (`tier_id`),
  CONSTRAINT `fk_component_instance_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_instance_2` FOREIGN KEY (`component_template_id`) REFERENCES `component_template` (`component_template_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_instance_3` FOREIGN KEY (`component_id`) REFERENCES `component` (`component_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_instance_4` FOREIGN KEY (`tier_id`) REFERENCES `tier` (`tier_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_template`
--

CREATE TABLE `component_template` (
  `component_template_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `component_template_name` char(45) NOT NULL,
  `component_template_directory` char(45) NOT NULL,
  `component_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`component_template_id`),
  UNIQUE KEY `component_template_UNIQUE` (`component_template_name`),
  KEY `fk_component_template_1` (`component_id`),
  CONSTRAINT `fk_component_template_1` FOREIGN KEY (`component_id`) REFERENCES `component` (`component_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_template_attr`
--

CREATE TABLE `component_template_attr` (
  `template_component_id` int(8) unsigned NOT NULL,
  `template_component_attr_file` char(45) NOT NULL,
  `component_template_attr_field` char(45) NOT NULL,
  `component_template_attr_type` char(45) NOT NULL,
  PRIMARY KEY (`template_component_id`),
  KEY `fk_component_template_attr_1` (`template_component_id`),
  CONSTRAINT `fk_component_template_attr_1` FOREIGN KEY (`template_component_id`) REFERENCES `component_template` (`component_template_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Orchestrator tables
--

--
-- Table structure for orchestrator table `condition`
--

CREATE TABLE `rulecondition` (
  `rulecondition_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `rulecondition_var` char(64) NOT NULL,
  `rulecondition_time_laps` char(32) NOT NULL,
  `rulecondition_consolidation_func` char(32) NOT NULL,
  `rulecondition_transformation_func` char(32) NOT NULL,
  `rulecondition_operator` char(32) NOT NULL,
  `rulecondition_value` int(8) unsigned NOT NULL,
  `rule_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`rulecondition_id`),
  KEY `fk_rulecondition_1` (`rule_id`),
  CONSTRAINT `fk_rulecondition_1` FOREIGN KEY (`rule_id`) REFERENCES `rule` (`rule_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for orchestrator table `rule`
--

CREATE TABLE `rule` (
  `rule_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `rule_condition` char(128) NOT NULL,
  `rule_action` char(32) NOT NULL,
  `cluster_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`rule_id`),
  KEY `fk_rule_1` (`cluster_id`),
  CONSTRAINT `fk_rule_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for orchestrator table `workload_characteristic`
--

CREATE TABLE `workload_characteristic` (
  `wc_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `wc_visit_ratio` int(8) NOT NULL,
  `wc_service_time` int(8) NOT NULL,
  `wc_delay` int(8) NOT NULL,
  `wc_think_time` int(8) NOT NULL,
  `cluster_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`wc_id`),
  KEY `fk_wc_1` (`cluster_id`),
  CONSTRAINT `fk_wc_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for orchestrator table `qos_constraint`
--

CREATE TABLE `qos_constraint` (
  `constraint_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `constraint_max_latency` int(8) NOT NULL,
  `constraint_max_abort_rate` int(8) NOT NULL,
  `cluster_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`constraint_id`),
  KEY `fk_constraint_1` (`cluster_id`),
  CONSTRAINT `fk_constraint_1` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Monitor tables
--

--
-- Table structure for table `indicatorset` (monitor)
--

CREATE TABLE `indicatorset` (
  `indicatorset_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `indicatorset_name` char(16) NOT NULL,
  `indicatorset_provider` char(32) NOT NULL,
  `indicatorset_type` char(32) NOT NULL,
  `indicatorset_component` char(32),
  `indicatorset_max` char(128),
  PRIMARY KEY (`indicatorset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `indicator` (monitor)
--

CREATE TABLE `indicator` (
  `indicator_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `indicator_name` char(32) NOT NULL,
  `indicator_oid` char(64) NOT NULL,
  `indicator_min` int(8) unsigned,
  `indicator_max` int(8) unsigned,
  `indicator_color` char(8),
  `indicatorset_id` int(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`indicator_id`),
  KEY `fk_indicator_1` (`indicatorset_id`),
  CONSTRAINT `fk_indicator_1` FOREIGN KEY (`indicatorset_id`) REFERENCES `indicatorset` (`indicatorset_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `collect` (monitor)
--

CREATE TABLE `collect` (
  `indicatorset_id` int(8) unsigned NOT NULL,
  `cluster_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`indicatorset_id`, `cluster_id`),
  KEY `fk_collect_1` (`indicatorset_id`),
  KEY `fk_collect_2` (`cluster_id`),
  CONSTRAINT `fk_collect_1` FOREIGN KEY (`indicatorset_id`) REFERENCES `indicatorset` (`indicatorset_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_collect_2` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `graph` (monitor)
--

CREATE TABLE `graph` (
  `indicatorset_id` int(8) unsigned NOT NULL,
  `cluster_id` int(8) unsigned NOT NULL,
  `graph_type` char(32) NOT NULL,
  `graph_percent` int(1) unsigned,
  `graph_sum` int(1) unsigned,
  `graph_indicators` char(128),
  PRIMARY KEY (`indicatorset_id`, `cluster_id`),
  KEY `fk_graph_1` (`indicatorset_id`),
  KEY `fk_graph_2` (`cluster_id`),
  CONSTRAINT `fk_graph_1` FOREIGN KEY (`indicatorset_id`) REFERENCES `indicatorset` (`indicatorset_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_graph_2` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Entity tables
--

--
-- Table structure for table `entity`
--

CREATE TABLE `entity` (
  `entity_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `ingroups`
--

CREATE TABLE `ingroups` (
  `gp_id` int(8) unsigned NOT NULL,
  `entity_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`gp_id`,`entity_id`),
  KEY `fk_grouping_1` (`entity_id`),
  KEY `fk_grouping_2` (`gp_id`),
  CONSTRAINT `fk_grouping_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_grouping_2` FOREIGN KEY (`gp_id`) REFERENCES `gp` (`gp_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `entityright`
--

CREATE TABLE `entityright` (
  `entityright_id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `entityright_consumed_id` int(8) unsigned NOT NULL,
  `entityright_consumer_id` int(8) unsigned NOT NULL,
  `entityright_method` char(64) NOT NULL,
  PRIMARY KEY (`entityright_id`),
  UNIQUE KEY `entityright_right` (`entityright_consumed_id`,`entityright_consumer_id`,`entityright_method`),
  KEY `fk_entityright_1` (`entityright_consumed_id`),
  KEY `fk_entityright_2` (`entityright_consumer_id`),
  CONSTRAINT `fk_entityright_1` FOREIGN KEY (`entityright_consumed_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_entityright_2` FOREIGN KEY (`entityright_consumer_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `user_entity`
--

CREATE TABLE `user_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `user_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`user_id`),
  UNIQUE KEY `fk_user_entity_1` (`entity_id`),
  UNIQUE KEY `fk_user_entity_2` (`user_id`),
  CONSTRAINT `fk_user_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_user_entity_2` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `distribution_entity`
--

CREATE TABLE `distribution_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `distribution_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`distribution_id`),
  UNIQUE KEY `fk_distribution_entity_1` (`entity_id`),
  UNIQUE KEY `fk_distribution_entity_2` (`distribution_id`),
  CONSTRAINT `fk_distribution_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_distribution_entity_2` FOREIGN KEY (`distribution_id`) REFERENCES `distribution` (`distribution_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `host_entity`
--

CREATE TABLE `host_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `host_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`host_id`),
  UNIQUE KEY `fk_host_entity_1` (`entity_id`),
  UNIQUE KEY `fk_host_entity_2` (`host_id`),
  CONSTRAINT `fk_host_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_host_entity_2` FOREIGN KEY (`host_id`) REFERENCES `host` (`host_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `powersupplycard_entity`
--

CREATE TABLE `powersupplycard_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `powersupplycard_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`powersupplycard_id`),
  UNIQUE KEY `fk_powersupplycard_entity_1` (`entity_id`),
  UNIQUE KEY `fk_powersupplycard_entity_2` (`powersupplycard_id`),
  CONSTRAINT `fk_powersupplycard_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_powersupplycard_entity_2` FOREIGN KEY (`powersupplycard_id`) REFERENCES `powersupplycard` (`powersupplycard_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operation_entity`
--

CREATE TABLE `operation_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `operation_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`operation_id`),
  UNIQUE KEY `fk_operation_entity_1` (`entity_id`),
  UNIQUE KEY `fk_operation_entity_2` (`operation_id`),
  CONSTRAINT `fk_operation_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_operation_entity_2` FOREIGN KEY (`operation_id`) REFERENCES `operation` (`operation_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `systemimage_entity`
--

CREATE TABLE `systemimage_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `systemimage_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`systemimage_id`),
  UNIQUE KEY `fk_systemimage_entity_1` (`entity_id`),
  UNIQUE KEY `fk_systemimage_entity_2` (`systemimage_id`),
  CONSTRAINT `fk_systemimage_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_systemimage_entity_2` FOREIGN KEY (`systemimage_id`) REFERENCES `systemimage` (`systemimage_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `component_instance_entity`
--

CREATE TABLE `component_instance_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `component_instance_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`component_instance_id`),
  UNIQUE KEY `fk_component_instance_entity_1` (`entity_id`),
  UNIQUE KEY `fk_component_instance_entity_2` (`component_instance_id`),
  CONSTRAINT `fk_component_instance_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_component_instance_entity_2` FOREIGN KEY (`component_instance_id`) REFERENCES `component_instance` (`component_instance_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `message_entity`
--

CREATE TABLE `message_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `message_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`message_id`),
  UNIQUE KEY `fk_message_entity_1` (`entity_id`),
  UNIQUE KEY `fk_message_entity_2` (`message_id`),
  CONSTRAINT `fk_message_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_message_entity_2` FOREIGN KEY (`message_id`) REFERENCES `message` (`message_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `kernel_entity`
--

CREATE TABLE `kernel_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `kernel_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`kernel_id`),
  UNIQUE KEY `fk_kernel_entity_1` (`entity_id`),
  UNIQUE KEY `fk_kernel_entity_2` (`kernel_id`),
  CONSTRAINT `fk_kernel_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_kernel_entity_2` FOREIGN KEY (`kernel_id`) REFERENCES `kernel` (`kernel_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `operationtype_entity`
--

CREATE TABLE `operationtype_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `operationtype_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`operationtype_id`),
  UNIQUE KEY `fk_operationtype_entity_1` (`entity_id`),
  UNIQUE KEY `fk_operationtype_entity_2` (`operationtype_id`),
  CONSTRAINT `fk_operationtype_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_operationtype_entity_2` FOREIGN KEY (`operationtype_id`) REFERENCES `operationtype` (`operationtype_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `gp_entity`
--

CREATE TABLE `gp_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `gp_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`gp_id`),
  UNIQUE KEY `fk_gp_entity_1` (`entity_id`),
  UNIQUE KEY `fk_gp_entity_2` (`gp_id`),
  CONSTRAINT `fk_gp_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_gp_entity_2` FOREIGN KEY (`gp_id`) REFERENCES `gp` (`gp_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `hostmodel_entity`
--

CREATE TABLE `hostmodel_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `hostmodel_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`hostmodel_id`),
  UNIQUE KEY `fk_hostmodel_entity_1` (`entity_id`),
  UNIQUE KEY `fk_hostmodel_entity_2` (`hostmodel_id`),
  CONSTRAINT `fk_hostmodel_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_hostmodel_entity_2` FOREIGN KEY (`hostmodel_id`) REFERENCES `hostmodel` (`hostmodel_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `processormodel_entity`
--

CREATE TABLE `processormodel_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `processormodel_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`processormodel_id`),
  UNIQUE KEY `fk_processormodel_entity_1` (`entity_id`),
  UNIQUE KEY `fk_processormodel_entity_2` (`processormodel_id`),
  CONSTRAINT `fk_processormodel_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_processormodel_entity_2` FOREIGN KEY (`processormodel_id`) REFERENCES `processormodel` (`processormodel_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `powersupplycardmodel_entity`
--

CREATE TABLE `powersupplycardmodel_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `powersupplycardmodel_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`powersupplycardmodel_id`),
  UNIQUE KEY `fk_powersupplycardmodel_entity_1` (`entity_id`),
  UNIQUE KEY `fk_powersupplycardmodel_entity_2` (`powersupplycardmodel_id`),
  CONSTRAINT `fk_powersupplycardmodel_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_powersupplycardmodel_entity_2` FOREIGN KEY (`powersupplycardmodel_id`) REFERENCES `powersupplycardmodel` (`powersupplycardmodel_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `cluster_entity`
--

CREATE TABLE `cluster_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `cluster_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`cluster_id`),
  UNIQUE KEY `fk_cluster_entity_1` (`entity_id`),
  UNIQUE KEY `fk_cluster_entity_2` (`cluster_id`),
  CONSTRAINT `fk_cluster_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_cluster_entity_2` FOREIGN KEY (`cluster_id`) REFERENCES `cluster` (`cluster_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `tier_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `tier_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`tier_id`),
  UNIQUE KEY `fk_tier_entity_1` (`entity_id`),
  UNIQUE KEY `fk_tier_entity_2` (`tier_id`),
  CONSTRAINT `fk_tier_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_tier_entity_2` FOREIGN KEY (`tier_id`) REFERENCES `tier` (`tier_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `infrastructure_entity` (
  `entity_id` int(8) unsigned NOT NULL,
  `infrastructure_id` int(8) unsigned NOT NULL,
  PRIMARY KEY (`entity_id`,`infrastructure_id`),
  UNIQUE KEY `fk_infrastructure_entity_1` (`entity_id`),
  UNIQUE KEY `fk_infrastructure_entity_2` (`infrastructure_id`),
  CONSTRAINT `fk_infrastructure_entity_1` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fk_infrastructure_entity_2` FOREIGN KEY (`infrastructure_id`) REFERENCES `infrastructure` (`infrastructure_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

SET foreign_key_checks=1;

