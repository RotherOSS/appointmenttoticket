# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2025 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker::AppointmentTicket;

use strict;
use warnings;

use parent                        qw(Kernel::System::Daemon::DaemonModules::BaseTaskWorker);
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CustomerUser',
    'Kernel::System::DB',
    'Kernel::System::Daemon::SchedulerDB',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::HTMLUtils',
    'Kernel::System::LinkObject',
    'Kernel::System::Log',
    'Kernel::System::Calendar::Appointment',
    'Kernel::System::Ticket',
    'Kernel::System::Ticket::Article',
);

=head1 NAME

Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker::AppointmentTicket - Scheduler daemon task handler module for AppointmentTicket

=head1 DESCRIPTION

This task handler executes appointment ticket jobs.

=head1 PUBLIC INTERFACE

=head2 new()

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $TaskHandlerObject = $Kernel::OM-Get('Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker::AppointmentTicket');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug}      = $Param{Debug};
    $Self->{WorkerName} = 'Worker: AppointmentTicket';

    return $Self;
}

=head2 Run()

performs the selected task.

    my $Result = $TaskHandlerObject->Run(
        TaskID   => 123,
        TaskName => 'some name',    # optional
        Data     => {               # appointment id as got from Kernel::System::Calendar::Appointment::AppointmentGet()
            NotifyTime => '2016-08-02 03:59:00',
        },
    );

Returns:

    $Result = 1; # or fail in case of an error

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check task params
    my $CheckResult = $Self->_CheckTaskParams(
        %Param,
        NeededDataAttributes =>
            [
                'AppointmentTicket', 'AppointmentID'
            ],
    );

    # stop execution if an error in params is detected
    return if !$CheckResult;

    my $DBObject                  = $Kernel::OM->Get('Kernel::System::DB');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $ConfigObject              = $Kernel::OM->Get('Kernel::Config');

    my $Config = $ConfigObject->Get('Ticket::Frontend::AgentAppointmentEdit');

    if ( $Self->{Debug} ) {
        print "    $Self->{WorkerName} executes task: $Param{TaskName}\n";
    }

    # fetching customer user from selectedcustomeruser
    my %CustomerUser = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
        User => $Param{Data}->{AppointmentTicket}->{SelectedCustomerUser},
    );

    # create the appointment ticket
    my $TicketID = $Kernel::OM->Get('Kernel::System::Ticket')->TicketCreate(
        $Param{Data}->{AppointmentTicket}->%*,
        CustomerUser => %CustomerUser ? $CustomerUser{UserLogin} : $Param{Data}->{AppointmentTicket}->{SelectedCustomerUser},
    );

    if ( !$TicketID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Could not trigger ticket appointment for AppointmentID $Param{Data}->{AppointmentID}!",
        );
    }

    # set dynamic fields for ticket
    my @DynamicFieldConfigs;
    my %DynamicFields;
    if ( $Param{Data}->{AppointmentTicket}->{DynamicFields} ) {

        # Fetch dynamic field configs
        if ( defined $Config->{DynamicField} ) {
            my $DynamicFieldConfigsRef = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
                Valid       => 1,
                ObjectType  => [ 'Ticket', 'Article' ],
                FieldFilter => $Config->{DynamicField} || {},
            );
            @DynamicFieldConfigs = defined $DynamicFieldConfigsRef ? @{$DynamicFieldConfigsRef} : ();
        }

        # set ticket dynamic fields
        %DynamicFields = %{ $Param{Data}->{AppointmentTicket}->{DynamicFields} };
        DYNAMICFIELDTICKET:
        for my $DynamicFieldConfig (@DynamicFieldConfigs) {
            next DYNAMICFIELDTICKET if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELDTICKET if $DynamicFieldConfig->{ObjectType} ne 'Ticket';
            if ( $DynamicFields{ $DynamicFieldConfig->{Name} } ) {

                # set the value
                my $Success = $DynamicFieldBackendObject->ValueSet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                    ObjectID           => $TicketID,
                    Value              => $Param{Data}->{AppointmentTicket}->{DynamicFields}->{ $DynamicFieldConfig->{Name} },
                    UserID             => $Param{Data}->{AppointmentTicket}->{UserID},
                );
            }
        }
    }

    # preparing from data
    my $ArticleFrom;
    my @CustomerUsers = split /,/, $Param{Data}->{AppointmentTicket}->{CustomerUser};
    for my $CustomerUser (@CustomerUsers) {
        my %CustomerUserData = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
            User => $CustomerUser,
        );
        my $CustomerUserString
            = %CustomerUserData ? "\"$CustomerUserData{UserFirstname} $CustomerUserData{UserLastname}\" <$CustomerUserData{UserEmail}>" : $CustomerUser;
        if ($ArticleFrom) {
            $ArticleFrom .= ", $CustomerUserString";
        }
        else {
            $ArticleFrom = "$CustomerUserString";
        }
    }

    my $ArticleObject        = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $ArticleBackendObject = $ArticleObject->BackendForChannel( ChannelName => 'Internal' );
    my $ArticleID            = $ArticleBackendObject->ArticleCreate(
        TicketID             => $TicketID,
        SenderType           => 'system',
        IsVisibleForCustomer => $Param{Data}->{AppointmentTicket}->{ArticleVisibleForCustomer} || 0,
        From                 => $ArticleFrom,
        To                   => $Param{Data}->{AppointmentTicket}->{UserID},
        Subject              => $Param{Data}->{AppointmentTicket}->{Subject},
        Body                 => $Kernel::OM->Get('Kernel::System::HTMLUtils')->ToHTML( String => $Param{Data}->{AppointmentTicket}->{Content} ),
        MimeType             => 'text/html',
        Charset              => 'utf-8',
        UserID               => $Param{Data}->{AppointmentTicket}->{UserID},
        HistoryType          => 'Misc',
        HistoryComment       => 'Automatically created ticket from appointment',
        AutoResponseType     => ( $ConfigObject->Get('AutoResponseForWebTickets') )
        ? 'auto reply'
        : '',
        OrigHeader => {
            From    => $ArticleFrom,
            To      => $Param{Data}->{AppointmentTicket}->{UserID},
            Subject => $Param{Data}->{AppointmentTicket}->{Subject},
            Body    => $Param{Data}->{AppointmentTicket}->{Content},
        },
        Queue => $Param{Data}->{AppointmentTicket}->{QueueID},
    );

    if ( !$ArticleID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Could not create article for ticket $TicketID from appointment $Param{Data}->{AppointmentID}!",
        );
    }

    # set article dynamic fields
    if ( $Param{Data}->{AppointmentTicket}->{DynamicFields} ) {
        DYNAMICFIELDARTICLE:
        for my $DynamicFieldConfig (@DynamicFieldConfigs) {
            next DYNAMICFIELDARTICLE if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELDARTICLE if $DynamicFieldConfig->{ObjectType} ne 'Article';
            if ( $DynamicFields{ $DynamicFieldConfig->{Name} } ) {

                # set the value
                my $Success = $DynamicFieldBackendObject->ValueSet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                    ObjectID           => $ArticleID,
                    Value              => $Param{Data}->{AppointmentTicket}->{DynamicFields}->{ $DynamicFieldConfig->{Name} },
                    UserID             => $Param{Data}->{AppointmetTicket}->{UserID},
                );
            }
        }
    }

    my %Appointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet(
        AppointmentID => $Param{Data}->{AppointmentID},
    );

    # link the tickets
    $Kernel::OM->Get('Kernel::System::LinkObject')->LinkAdd(
        SourceObject => 'Appointment',
        SourceKey    => $Appointment{AppointmentID},
        TargetObject => 'Ticket',
        TargetKey    => $TicketID,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => $Param{Data}->{AppointmentTicket}->{UserID},
    );

    # delete future task id from appointment
    my $Success = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentUpdate(
        %Appointment,
        UserID       => $Param{Data}->{AppointmentTicket}->{UserID},
        FutureTaskID => undef,
    );

    # Check if appointment is recurring and if so, create next future task for appointment which is in the future and closest to now
    if ( $Appointment{Recurring} || $Appointment{ParentID} ) {

        # Get all related appointments
        my @Appointments = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentList(
            CalendarID => $Appointment{CalendarID},
            ParentID   => $Appointment{ParentID} || $Appointment{AppointmentID},
        );

        # Push parent into list since AppointmentList with filter ParentID does not include the parent itself
        my %ParentAppointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet(
            AppointmentID => ( $Appointment{ParentID} ? $Appointment{ParentID} : $Appointment{AppointmentID} )
        );
        push @Appointments, \%ParentAppointment;

        my $CurrentTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime'
        );

        my $NextAppointment;
        my $TimeDiff;
        my $ExecutionTime;
        for my $AppointmentRef (@Appointments) {

            my $AppointmentExecutionTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentToTicketExecutionTime(
                        Data => {
                            TicketTime                      => $Param{Data}->{AppointmentTicket}->{Time},
                            TicketTemplate                  => $Param{Data}->{AppointmentTicket}->{Template},
                            TicketCustom                    => $Param{Data}->{AppointmentTicket}->{Custom},
                            TicketCustomRelativeUnitCount   => $Param{Data}->{AppointmentTicket}->{CustomRelativeUnitCount},
                            TicketCustomRelativeUnit        => $Param{Data}->{AppointmentTicket}->{CustomRelativeUnit},
                            TicketCustomRelativePointOfTime => $Param{Data}->{AppointmentTicket}->{CustomRelativePointOfTime},
                            TicketCustomDateTime            => $Param{Data}->{AppointmentTicket}->{CustomDateTime},
                        },
                        StartTime => $AppointmentRef->{StartTime},
                        EndTime   => $AppointmentRef->{EndTime},
                    ),
                },
            );
            if ( $AppointmentExecutionTimeObject->Compare( DateTimeObject => $CurrentTimeObject ) > 0 ) {
                my $DeltaResult = $AppointmentExecutionTimeObject->Delta( DateTimeObject => $CurrentTimeObject );
                if ( !defined $TimeDiff ) {
                    $NextAppointment = $AppointmentRef;
                    $TimeDiff        = $DeltaResult->{AbsoluteSeconds};
                    $ExecutionTime   = $AppointmentExecutionTimeObject->ToString();
                }
                elsif ( $DeltaResult->{AbsoluteSeconds} < $TimeDiff ) {
                    $NextAppointment = $AppointmentRef;
                    $TimeDiff        = $DeltaResult->{AbsoluteSeconds};
                    $ExecutionTime   = $AppointmentExecutionTimeObject->ToString();
                }
            }
        }

        if ($NextAppointment) {

            # update appointment in db
            $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentUpdate(
                $NextAppointment->%*,
                UserID            => $Param{Data}->{AppointmentTicket}->{UserID},
                AppointmentTicket => {
                    $Param{Data}->{AppointmentTicket}->%*,
                },
            );
        }

    }

    return $TicketID;
}

1;
