#    Copyright © 2011-2012 Hedera Technology SAS
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package EEntity::EComponent::EVsphere5;

use base "EEntity::EComponent";
use base "EManager::EHostManager::EVirtualMachineManager";

use strict;
use warnings;

use VMware::VIRuntime;
use Vsphere5Datacenter;
use Vsphere5Repository;
use Entity;
use Entity::Host::Hypervisor;

use Log::Log4perl "get_logger";
use Data::Dumper;
use Kanopya::Exceptions;

my $log = get_logger("executor");
my $errmsg;

=head2 addRepository

    Desc: Register a new repository for an host in Vsphere
    Args: $repository_name, $container_access 
    Return: newly created $repository object

=cut

sub addRepository {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => ['host', 
                                                      'repository_name', 
                                                      'container_access']);

    $self->negociateConnection();

    my $hypervisor_name     = $args{host}->host_hostname;
    my $container_access    = $args{container_access};
    my $container_access_ip = $container_access->container_access_ip;
    my $export_full_path    = $container_access->container_access_export;
    my @export_path         = split (':', $export_full_path);

    my $view = $self->findEntityView(view_type      => 'HostSystem',
                                     hash_filter    => {
                                         'name' => $hypervisor_name,
                                     });

    my $datastore = HostNasVolumeSpec->new( accessMode => 'readWrite',
                                            remoteHost => $container_access_ip,
                                            localPath  => $args{repository_name},
                                            remotePath => $export_path[1],
                    );

    my $dsmv = $self->getView(mo_ref=>$view->configManager->datastoreSystem);
}

=head2 startHost

    Desc: Create and start a vm

=cut

sub startHost {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => ['hypervisor', 'host']);

    $log->info('Calling startHost on EVSphere '. ref($self));

    $self->negociateConnection();

    my $host       = $args{host};
    my $hypervisor = $args{hypervisor};
    my $guest_id   = 'debian6_64Guest';

    $log->info('Start host on < hypervisor '. $hypervisor->id.' >');

    if (!defined $hypervisor) {
        my $errmsg = "Cannot add node in cluster ".$args{host}->getClusterId().", no hypervisor available";
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    my %host_conf;
    my $cluster     = Entity->get(id => $host->getClusterId());
    my $image       = $args{host}->getNodeSystemimage();
    #TODO fix this way to get image disk file type
    my $image_name  = $image->systemimage_name.'.raw';
    my $image_size  = $image->container->container_size;
    my $disk_params = $cluster->getManagerParameters(manager_type => 'disk_manager');
    my $host_params = $cluster->getManagerParameters(manager_type => 'host_manager');
    my $repository  = $self->getRepository(
                          container_access_id => $disk_params->{container_access_id}
                      );
    my $datacenter  = Vsphere5Datacenter->find(hash => { 
                          vsphere5_datacenter_id => $hypervisor->vsphere5_datacenter_id
                      });
    
    $host_conf{hostname}   = $host->host_hostname;
    $host_conf{hypervisor} = $hypervisor->host_hostname;
    $host_conf{datacenter} = $datacenter->vsphere5_datacenter_name;
    $host_conf{guest_id}   = $guest_id;
    $host_conf{datastore}  = $repository->repository_name;
    $host_conf{img_name}   = $image_name;
    $host_conf{img_size}   = $image_size;
    $host_conf{memory}     = $host_params->{ram};
    $host_conf{cores}      = $host_params->{core};
    $host_conf{network}    = 'VM Network';

    $log->debug('new VM configuration parameters: ');
    $log->debug(Dumper \%host_conf);

    #Create vm in vsphere
    $self->createVm(host_conf => \%host_conf);

    #Declare the vsphere5 vm in Kanopya
    $self->addVM(
        host     => $host->_getEntity(),
        guest_id => $guest_id,
    );

    #Power on the VM
    #We retrieve a view of the newly created VM
    my $hypervisor_hash_filter = {name => $hypervisor->host_hostname};
    my $hypervisor_view        = findEntityView(
                                    view_type   => 'HostSystem',
                                    hash_filter => $hypervisor_hash_filter,
                                 );
    my $vm_hash_filter        = {name => $host->host_hostname};
    my $vm_view               = findEntityView(
                                    view_type    => 'VirtualMachine',
                                    hash_filter  => $vm_hash_filter,
                                    begin_entity => $hypervisor_view,
                                );
    #Power On
    $vm_view->PowerOnVM();
}


=head2 createVm

    Desc: Create a new VM on a vSphere host 

=cut

sub createVm {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host_conf']);

    my %host_conf = %{$args{host_conf}};
    my $ds_path   = '['.$host_conf{datastore}.']';
    my $img_name  = $host_conf{img_name};
    my $img_size  = $host_conf{img_size};
    my $path      = $ds_path.' '.$img_name;
    my $host_view;
    my $datacenter_view;
    my $vm_folder_view;
    my $comp_res_view;
    my @vm_devices;

    $log->info('trying to get Hypervisor ' .$host_conf{hypervisor}. ' view from vsphere');

    #retrieve host view
        $host_view = $self->findEntityView(view_type   => 'HostSystem',
                                           hash_filter => {
                                               'name' => $host_conf{hypervisor},
                                           });

    #retrieve datacenter view
        $datacenter_view = $self->findEntityview(view_type   => 'Datacenter',
                                                 hash_filter => {
                                                     name => $host_conf{datacenter}
                                                 });

    #Generate vm's devices specifications
    my $controller_vm_dev_conf_spec = create_conf_spec();
    push(@vm_devices, $controller_vm_dev_conf_spec);

    my $disk_vm_dev_conf_spec = create_virtual_disk(path => $path, disksize => $img_size);
    push(@vm_devices, $disk_vm_dev_conf_spec);

    my %net_settings = get_network(network_name => $host_conf{network},
                                    poweron      => 0,
                                    host_view    => $host_view);
    push(@vm_devices, $net_settings{network_conf});

    my $files = VirtualMachineFileInfo->new(logDirectory      => undef,
                                            snapshotDirectory => undef,
                                            suspendDirectory  => undef,
                                            vmPathName        => $ds_path);

    my $vm_config_spec = VirtualMachineConfigSpec->new(
                             name         => $host_conf{hostname},
                             memoryMB     => $host_conf{memory},
                             files        => $files,
                             numCPUs      => $host_conf{cores},
                             guestId      => $host_conf{guest_id},
                             deviceChange => \@vm_devices);

    #retrieve the vm folder from vsphere inventory
    $vm_folder_view = $self->getView(mo_ref => $datacenter_view->vmFolder);

    #retrieve the host parent view
    $comp_res_view  = $self->getView(mo_ref => $host_view->parent);

    #finally create the VM
    eval {
        $vm_folder_view->CreateVM(config => $vm_config_spec,
                                  pool   => $comp_res_view->resourcePool);
    };
    if ($@) {
        $errmsg = 'Error creating the virtual machine on host '.$host_conf{hypervisor}.': '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

}

=head2 scaleCpu

    Desc: Scale In CPU for virtual machine
    Args: $host (the VM's view), $cpu_number (the new number of CPUs to be set)
    
=cut

sub scaleCpu {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cpu_number' ]);

    my $host       = $args{host};
    my $cpu_number = $args{cpu_number};

    #Now we do the VM Scale In through ReconfigVM() method
    my $new_vm_config_spec = VirtualMachineConfigSpec->new(
                                 numCPUs => $cpu_number,
                             );
    eval {
            $host->ReconfigVM(
                spec => $new_vm_config_spec,
            );
    };
    if ($@) {
        $errmsg = 'Error scaling in CPU on virtual machine '.$host->name.': '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }
    #We Refresh the values of view
    #with corresponding server-side object values
    $host->update_view_data;
}

=head2 scaleMemory

    Desc: Scale In memory for virtual machine
    Args: $host (the VM's view), $memory (the new amount of memory to be set)
    
=cut

sub scaleMemory {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => ['host','memory']);

    my $host   = $args{host};
    my $memory = $args{memory};

    #Now we do the VM Scale In through ReconfigVM() method
    my $vm_new_config_spec = VirtualMachineConfigSpec->new(
                                 memoryMB => $memory  / 1024 / 1024,
                             );
    eval {
        $host->ReconfigVM(
            spec => $vm_new_config_spec,
        );
    };
    if ($@) {
        $errmsg = 'Error scaling in Memory on virtual machine '.$host->name.': '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }
    #We Refresh the values of view
    #with corresponding server-side object values
    $host->update_view_data;
}

sub create_conf_spec {
    my $controller;
    my $controller_vm_dev_conf_spec;

    eval {
        $controller =
            VirtualLsiLogicController->new(key => 0,
                                           device => [0],
                                           busNumber => 0,
                                           sharedBus => VirtualSCSISharing->new('noSharing')
            );

        $controller_vm_dev_conf_spec =
            VirtualDeviceConfigSpec->new(
                device => $controller,
                operation => VirtualDeviceConfigSpecOperation->new('add')
            );
    };
    if ($@) {
        $errmsg = 'Error creating the virtual machine controller configuration: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $controller_vm_dev_conf_spec;
}

sub create_virtual_disk {
    my %args     = @_;
    my $path     = $args{path};
    my $disksize = $args{disksize};

    my $disk_vm_dev_conf_spec;
    my $disk_backing_info;
    my $disk;
    
    eval {
        $disk_backing_info =
           VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                               fileName => $path);

        $disk = VirtualDisk->new(backing       => $disk_backing_info,
                                   controllerKey => 0,
                                   key           => 0,
                                   unitNumber    => 0,
                                   capacityInKB  => $disksize);

        $disk_vm_dev_conf_spec =
           VirtualDeviceConfigSpec->new(
               device        => $disk,
               operation     => VirtualDeviceConfigSpecOperation->new('add')
           );
    };
    if ($@) {
        $errmsg = 'Error creating the virtual machine disk configuration: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $disk_vm_dev_conf_spec;
}

sub get_network {
    my %args         = @_;
    my $network_name = $args{network_name};
    my $poweron      = $args{poweron};
    my $host_view    = $args{host_view};
    my $network      = undef;
    my $unit_num     = 1;  # 1 since 0 is used by disk

    eval {
        if($network_name) {
        #TODO Use get view from an Mother entity + Eval{};
            my $network_list = Vim::get_views(mo_ref_array => $host_view->network);
            foreach (@$network_list) {
                if($network_name eq $_->name) {
                    $network             = $_;
                    my $nic_backing_info =
                        VirtualEthernetCardNetworkBackingInfo->new(
                            deviceName => $network_name,
                            network    => $network
                        );

                    my $vd_connect_info =
                        VirtualDeviceConnectInfo->new(allowGuestControl => 1,
                                                      connected         => 0,
                                                      startConnected    => $poweron);

                    my $nic = VirtualPCNet32->new(backing     => $nic_backing_info,
                                                  key         => 0,
                                                  unitNumber  => $unit_num,
                                                  addressType => 'generated',
                                                  connectable => $vd_connect_info);

                    my $nic_vm_dev_conf_spec =
                        VirtualDeviceConfigSpec->new(
                            device => $nic,
                            operation => VirtualDeviceConfigSpecOperation->new('add')
                        );

                    return (error => 0, network_conf => $nic_vm_dev_conf_spec);
                }
            }

            if (!defined($network)) {
                # no network found
                return (error => 1);
            }
        }
    };
    if ($@) {
        $errmsg = 'Error creating the virtual machine network configuration: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    # default network will be used
    return (error => 2);
}

sub DESTROY {
    my $self = shift;

    $self->disconnect();
}

1;
