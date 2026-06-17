# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# $origin: otobo - 6efdc7bf2a3325277cd79a60f0f2407f8ad59e87 - Kernel/Modules/AgentAppointmentEdit.pm
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

package Kernel::Modules::AgentAppointmentEdit;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language              qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{EmptyString} = '-';

# RotherOSS / AppointmentToTicket
    # frontend specific config
    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    my $DynamicFieldList = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    $Self->{DynamicField}->%* = map { $_->{Name} => $_ } @{ $DynamicFieldList // [] };

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    # methods which are used to determine the possible values of the standard fields
    $Self->{FieldMethods} = [
        {
            FieldID => 'Dest',
            Method  => \&_GetTos
        },
        {
            FieldID => 'NextStateID',
            Method  => \&_GetStates
        },
        {
            FieldID => 'PriorityID',
            Method  => \&_GetPriorities
        },
        {
            FieldID => 'ServiceID',
            Method  => \&_GetServices
        },
        {
            FieldID => 'SLAID',
            Method  => \&_GetSLAs
        },
        {
            FieldID => 'TypeID',
            Method  => \&_GetTypes
        },
    ];

    # dependancies of standard fields which are not defined via ACLs
    $Self->{InternalDependancy} = {
        ServiceID => {
            SLAID     => 1,
            ServiceID => 1,    #CustomerUser updates can be submitted as ElementChanged: ServiceID
        },
        CustomerUser => {
            ServiceID => 1,
        },
    };
# EO AppointmentToTicket

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get names of all parameters
    my @ParamNames = $ParamObject->GetParamNames();

    # get params
    my %GetParam;
    PARAMNAME:
    for my $Key (@ParamNames) {

        # skip the Action parameter, it's giving BuildDateSelection problems for some reason
        next PARAMNAME if $Key eq 'Action';

        $GetParam{$Key} = $ParamObject->GetParam( Param => $Key );

        my %SafeGetParam = $Kernel::OM->Get('Kernel::System::HTMLUtils')->Safety(
            String       => $GetParam{$Key},
            NoApplet     => 1,
            NoObject     => 1,
            NoEmbed      => 1,
            NoSVG        => 1,
            NoImg        => 1,
            NoIntSrcLoad => 1,
            NoExtSrcLoad => 1,
            NoJavaScript => 1,
        );

        $GetParam{$Key} = $SafeGetParam{String};
    }

# RotherOSS / AppointmentToTicket
    # hash for check duplicated entries
    my %AddressesList;

    # MultipleCustomer From-field
    my @MultipleCustomer;
    my $CustomersNumber = $GetParam{'CustomerTicketCounterFromCustomer'} || 0;
    # Contains user name
    my $Selected = $GetParam{'CustomerSelected'} || '';

    # get check item object
    my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

    if ($CustomersNumber) {
        my $CustomerCounter = 1;
        for my $Count ( 0 ... $CustomersNumber ) {
            my $CustomerElement  = $GetParam{'CustomerTicketText_' . $Count};
            my $CustomerSelected = $Selected == $Count ? 'checked="checked"' : '';
            my $CustomerKey      = $GetParam{'CustomerKey_' . $Count} || '';

            if ($CustomerElement) {

                my $CountAux         = $CustomerCounter++;
                my $CustomerError    = '';
                my $CustomerErrorMsg = 'CustomerGenericServerErrorMsg';
                my $CustomerDisabled = '';

                if ( $GetParam{From} ) {
                    $GetParam{From} .= ', ' . $CustomerElement;
                }
                else {
                    $GetParam{From} = $CustomerElement;
                }

                # check email address
                for my $Email ( Mail::Address->parse($CustomerElement) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) )
                    {
                        $CustomerErrorMsg = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerError = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElement} && $CustomerError eq '' ) {
                    $CustomerErrorMsg = 'IsDuplicatedServerErrorMsg';
                    $CustomerError    = 'ServerError';
                }

                if ( $CustomerError ne '' ) {
                    $CustomerDisabled = 'disabled="disabled"';
                    $CountAux         = $Count . 'Error';
                }
                push @MultipleCustomer, {
                    Count            => $CountAux,
                    CustomerElement  => $CustomerElement,
                    CustomerSelected => $CustomerSelected,
                    CustomerKey      => $CustomerKey,
                    CustomerError    => $CustomerError,
                    CustomerErrorMsg => $CustomerErrorMsg,
                    CustomerDisabled => $CustomerDisabled,
                };
                $AddressesList{$CustomerElement} = 1;
            }
        }
    }

# EO AppointmentToTicket

    my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
# RotherOSS / AppointmentToTicket
    my $Config = $ConfigObject->Get("Ticket::Frontend::AgentAppointmentEdit");
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $FieldRestrictionsObject = $Kernel::OM->Get('Kernel::System::Ticket::FieldRestrictions');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
# EO AppointmentToTicket
    my $LayoutObject      = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $CalendarObject    = $Kernel::OM->Get('Kernel::System::Calendar');
    my $AppointmentObject = $Kernel::OM->Get('Kernel::System::Calendar::Appointment');
    my $PluginObject      = $Kernel::OM->Get('Kernel::System::Calendar::Plugin');

    my $JSON = $LayoutObject->JSONEncode( Data => [] );

    my %PermissionLevel = (
        'ro'        => 1,
        'move_into' => 2,
        'create'    => 3,
        'note'      => 4,
        'owner'     => 5,
        'priority'  => 6,
        'rw'        => 7,
    );

    my $Permissions = 'rw';

#RotherOSS / AppointmentToTicket
    # get Dynamic fields for ParamObject
    my %DynamicFieldValues;

    # cycle through the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( values $Self->{DynamicField}->%* ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value from the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ParamObject        => $ParamObject,
            LayoutObject       => $LayoutObject,
        );
    }

    # convert dynamic field values into a structure for ACLs
    my %DynamicFieldACLParameters;
    DYNAMICFIELD:
    for my $DynamicField ( sort keys %DynamicFieldValues ) {
        next DYNAMICFIELD if !$DynamicField;
        next DYNAMICFIELD if !defined $DynamicFieldValues{$DynamicField};

        $DynamicFieldACLParameters{ 'DynamicField_' . $DynamicField } = $DynamicFieldValues{$DynamicField};
    }
    $GetParam{DynamicField} = \%DynamicFieldACLParameters;
#EO AppointmentToTicket
    # challenge token check
    $LayoutObject->ChallengeTokenCheck();

    # ------------------------------------------------------------ #
    # edit mask
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'EditMask' ) {

        # get all user's valid calendars
        my $ValidID = $Kernel::OM->Get('Kernel::System::Valid')->ValidLookup(
            Valid => 'valid',
        );
        my @Calendars = $CalendarObject->CalendarList(
            UserID  => $Self->{UserID},
            ValidID => $ValidID,
        );

        # transform data for select box
        my @CalendarData = map {
            {
                Key   => $_->{CalendarID},
                Value => $_->{CalendarName},
            }
        } @Calendars;

        # transform data for ID lookup
        my %CalendarLookup = map {
            $_->{CalendarID} => $_->{CalendarName}
        } @Calendars;

        for my $Calendar (@CalendarData) {

            # check permissions
            my $CalendarPermission = $CalendarObject->CalendarPermissionGet(
                CalendarID => $Calendar->{Key},
                UserID     => $Self->{UserID},
            );

            if ( $PermissionLevel{$CalendarPermission} < 3 ) {

                # permissions < create
                $Calendar->{Disabled} = 1;
            }
        }

        # define year boundaries
        my ( %YearPeriodPast, %YearPeriodFuture );
        for my $Field (qw (Start End RecurrenceUntil)) {
            $YearPeriodPast{$Field} = $YearPeriodFuture{$Field} = 5;
        }

        # do not use date selection time zone calculation by default
        my $OverrideTimeZone = 1;

        my %Appointment;
        if ( $GetParam{AppointmentID} ) {
            %Appointment = $AppointmentObject->AppointmentGet(
                AppointmentID => $GetParam{AppointmentID},
            );

            # non-existent appointment
            if ( !$Appointment{AppointmentID} ) {
                my $Output = $LayoutObject->Error(
                    Message => Translatable('Appointment not found!'),
                );

                return $LayoutObject->Attachment(
                    NoCache     => 1,
                    ContentType => 'text/html',
                    Charset     => $LayoutObject->{UserCharset},
                    Content     => $Output,
                    Type        => 'inline',
                );
            }

            # use time zone calculation if editing existing appointments
            # but only if not dealing with an all day appointment
            else {
                $OverrideTimeZone = $Appointment{AllDay} || 0;
            }

            # check permissions
            $Permissions = $CalendarObject->CalendarPermissionGet(
                CalendarID => $Appointment{CalendarID},
                UserID     => $Self->{UserID},
            );

            # Get start time components.
            my $StartTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{StartTime},
                },
            );
            my $StartTimeSettings = $StartTimeObject->Get();
            my $StartTimeComponents;
            for my $Key ( sort keys %{$StartTimeSettings} ) {
                $StartTimeComponents->{"Start$Key"} = $StartTimeSettings->{$Key};
            }

            # Get end time components.
            my $EndTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{EndTime},
                },
            );

            # End times for all day appointments are inclusive, subtract whole day.
            if ( $Appointment{AllDay} ) {
                $EndTimeObject->Subtract(
                    Days => 1,
                );
                if ( $EndTimeObject < $StartTimeObject ) {
                    $EndTimeObject = $StartTimeObject->Clone();
                }
            }

            my $EndTimeSettings = $EndTimeObject->Get();
            my $EndTimeComponents;
            for my $Key ( sort keys %{$EndTimeSettings} ) {
                $EndTimeComponents->{"End$Key"} = $EndTimeSettings->{$Key};
            }

            %Appointment = ( %Appointment, %{$StartTimeComponents}, %{$EndTimeComponents} );

            # Get recurrence until components.
            if ( $Appointment{RecurrenceUntil} ) {
                my $RecurrenceUntilTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $Appointment{RecurrenceUntil},
                    },
                );
                my $RecurrenceUntilSettings = $RecurrenceUntilTimeObject->Get();
                my $RecurrenceUntilComponents;
                for my $Key ( sort keys %{$EndTimeSettings} ) {
                    $RecurrenceUntilComponents->{"RecurrenceUntil$Key"} = $RecurrenceUntilSettings->{$Key};
                }

                %Appointment = ( %Appointment, %{$RecurrenceUntilComponents} );
            }

            # Recalculate year boundaries for build selection method.
            my $DateTimeObject   = $Kernel::OM->Create('Kernel::System::DateTime');
            my $DateTimeSettings = $DateTimeObject->Get();

            for my $Field (qw(Start End RecurrenceUntil)) {
                if ( $Appointment{"${Field}Year"} ) {
                    my $Diff = $Appointment{"${Field}Year"} - $DateTimeSettings->{Year};
                    if ( $Diff > 0 && abs $Diff > $YearPeriodFuture{$Field} ) {
                        $YearPeriodFuture{$Field} = abs $Diff;
                    }
                    elsif ( $Diff < 0 && abs $Diff > $YearPeriodPast{$Field} ) {
                        $YearPeriodPast{$Field} = abs $Diff;
                    }
                }
            }

            if ( $Appointment{Recurring} ) {
                my $RecurrenceType = $GetParam{RecurrenceType} || $Appointment{RecurrenceType};

                if ( $RecurrenceType eq 'CustomWeekly' ) {

                    my $DayOffset = $Self->_DayOffsetGet(
                        Time => $Appointment{StartTime},
                    );

                    if ( defined $GetParam{Days} ) {

                        # check parameters
                        $Appointment{Days} = $GetParam{Days};
                    }
                    else {
                        my @Days = @{ $Appointment{RecurrenceFrequency} };

                        # display selected days according to user timezone
                        if ($DayOffset) {
                            for my $Day (@Days) {
                                $Day += $DayOffset;

                                if ( $Day == 8 ) {
                                    $Day = 1;
                                }
                            }
                        }

                        $Appointment{Days} = join( ",", @Days );
                    }
                }
                elsif ( $RecurrenceType eq 'CustomMonthly' ) {

                    my $DayOffset = $Self->_DayOffsetGet(
                        Time => $Appointment{StartTime},
                    );

                    if ( defined $GetParam{MonthDays} ) {

                        # check parameters
                        $Appointment{MonthDays} = $GetParam{MonthDays};
                    }
                    else {
                        my @MonthDays = @{ $Appointment{RecurrenceFrequency} };

                        # display selected days according to user timezone
                        if ($DayOffset) {
                            for my $MonthDay (@MonthDays) {
                                $MonthDay += $DayOffset;
                                if ( $DateTimeSettings->{Day} == 32 ) {
                                    $MonthDay = 1;
                                }
                            }
                        }
                        $Appointment{MonthDays} = join( ",", @MonthDays );
                    }
                }
                elsif ( $RecurrenceType eq 'CustomYearly' ) {

                    my $DayOffset = $Self->_DayOffsetGet(
                        Time => $Appointment{StartTime},
                    );

                    if ( defined $GetParam{Months} ) {

                        # check parameters
                        $Appointment{Months} = $GetParam{Months};
                    }
                    else {
                        my @Months = @{ $Appointment{RecurrenceFrequency} };
                        $Appointment{Months} = join( ",", @Months );
                    }
                }
            }

            # Check if dealing with ticket appointment.
            if ( $Appointment{TicketAppointmentRuleID} ) {
                $GetParam{TicketID} = $CalendarObject->TicketAppointmentTicketID(
                    AppointmentID => $Appointment{AppointmentID},
                );

                my $Rule = $CalendarObject->TicketAppointmentRuleGet(
                    CalendarID => $Appointment{CalendarID},
                    RuleID     => $Appointment{TicketAppointmentRuleID},
                );

                # Get date types from the ticket appointment rule.
                if ( IsHashRefWithData($Rule) ) {
                    for my $Type (qw(StartDate EndDate)) {
                        if (
                            $Rule->{$Type} eq 'FirstResponseTime'
                            || $Rule->{$Type} eq 'UpdateTime'
                            || $Rule->{$Type} eq 'SolutionTime'
                            || $Rule->{$Type} eq 'PendingTime'
                            )
                        {
                            $GetParam{ReadOnlyStart}    = 1 if $Type eq 'StartDate';
                            $GetParam{ReadOnlyDuration} = 1 if $Type eq 'EndDate';
                        }
                        elsif ( $Rule->{$Type} =~ /^Plus_[0-9]+$/ ) {
                            $GetParam{ReadOnlyDuration} = 1;
                        }
                    }
                }
            }
        }

        # get selected timestamp
        my $SelectedTimestamp = sprintf(
            "%04d-%02d-%02d 00:00:00",
            $Appointment{StartYear}  // $GetParam{StartYear},
            $Appointment{StartMonth} // $GetParam{StartMonth},
            $Appointment{StartDay}   // $GetParam{StartDay}
        );

        # Get current date components.
        my $SelectedSystemTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                String => $SelectedTimestamp,
            },
        );
        my $SelectedSystemTimeSettings = $SelectedSystemTimeObject->Get();

        # Set current date components if not defined.
        $Appointment{Days}      //= $SelectedSystemTimeSettings->{DayOfWeek};
        $Appointment{MonthDays} //= $SelectedSystemTimeSettings->{Day};
        $Appointment{Months}    //= $SelectedSystemTimeSettings->{Month};

        # calendar ID selection
        my $CalendarID = $Appointment{CalendarID} // $GetParam{CalendarID};

        # calendar name
        if ($CalendarID) {
            $Param{CalendarName} = $CalendarLookup{$CalendarID};
        }

        # calendar selection
        $Param{CalendarIDStrg} = $LayoutObject->BuildSelection(
            Data         => \@CalendarData,
            SelectedID   => $CalendarID,
            Name         => 'CalendarID',
            Multiple     => 0,
            Class        => 'Modernize Validate_Required',
            PossibleNone => 1,
        );

        # all day
        if (
            $GetParam{AllDay} ||
            ( $GetParam{AppointmentID} && $Appointment{AllDay} )
            )
        {
            $Param{AllDayString}  = Translatable('Yes');
            $Param{AllDayChecked} = 'checked ';

            # start date
            $Param{StartDate} = sprintf(
                "%04d-%02d-%02d",
                $Appointment{StartYear}  // $GetParam{StartYear},
                $Appointment{StartMonth} // $GetParam{StartMonth},
                $Appointment{StartDay}   // $GetParam{StartDay},
            );

            # end date
            $Param{EndDate} = sprintf(
                "%04d-%02d-%02d",
                $Appointment{EndYear}  // $GetParam{EndYear},
                $Appointment{EndMonth} // $GetParam{EndMonth},
                $Appointment{EndDay}   // $GetParam{EndDay},
            );
        }
        else {
            $Param{AllDayString}  = Translatable('No');
            $Param{AllDayChecked} = '';

            # start date
            $Param{StartDate} = sprintf(
                "%04d-%02d-%02d %02d:%02d:00",
                $Appointment{StartYear}   // $GetParam{StartYear},
                $Appointment{StartMonth}  // $GetParam{StartMonth},
                $Appointment{StartDay}    // $GetParam{StartDay},
                $Appointment{StartHour}   // $GetParam{StartHour},
                $Appointment{StartMinute} // $GetParam{StartMinute},
            );

            # end date
            $Param{EndDate} = sprintf(
                "%04d-%02d-%02d %02d:%02d:00",
                $Appointment{EndYear}   // $GetParam{EndYear},
                $Appointment{EndMonth}  // $GetParam{EndMonth},
                $Appointment{EndDay}    // $GetParam{EndDay},
                $Appointment{EndHour}   // $GetParam{EndHour},
                $Appointment{EndMinute} // $GetParam{EndMinute},
            );
        }

        # start date string
        $Param{StartDateString} = $LayoutObject->BuildDateSelection(
            %GetParam,
            %Appointment,
            Prefix                   => 'Start',
            StartHour                => $Appointment{StartHour}   // $GetParam{StartHour},
            StartMinute              => $Appointment{StartMinute} // $GetParam{StartMinute},
            Format                   => 'DateInputFormatLong',
            ValidateDateBeforePrefix => 'End',
            Validate                 => $Appointment{TicketAppointmentRuleID} && $GetParam{ReadOnlyStart} ? 0 : 1,
            YearPeriodPast           => $YearPeriodPast{Start},
            YearPeriodFuture         => $YearPeriodFuture{Start},
            OverrideTimeZone         => $OverrideTimeZone,
        );

        # end date string
        $Param{EndDateString} = $LayoutObject->BuildDateSelection(
            %GetParam,
            %Appointment,
            Prefix                  => 'End',
            EndHour                 => $Appointment{EndHour}   // $GetParam{EndHour},
            EndMinute               => $Appointment{EndMinute} // $GetParam{EndMinute},
            Format                  => 'DateInputFormatLong',
            ValidateDateAfterPrefix => 'Start',
            Validate                => $Appointment{TicketAppointmentRuleID} && $GetParam{ReadOnlyDuration} ? 0 : 1,
            YearPeriodPast          => $YearPeriodPast{End},
            YearPeriodFuture        => $YearPeriodFuture{End},
            OverrideTimeZone        => $OverrideTimeZone,
        );

        # get main object
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

        # check if team object is registered
        if ( $MainObject->Require( 'Kernel::System::Calendar::Team', Silent => 1 ) ) {

            my $TeamIDs = $Appointment{TeamID};
            if ( !$TeamIDs ) {
                my @TeamIDs = $ParamObject->GetArray( Param => 'TeamID[]' );
                $TeamIDs = \@TeamIDs;
            }

            my $ResourceIDs = $Appointment{ResourceID};
            if ( !$ResourceIDs ) {
                my @ResourceIDs = $ParamObject->GetArray( Param => 'ResourceID[]' );
                $ResourceIDs = \@ResourceIDs;
            }

            # get needed objects
            my $TeamObject = $Kernel::OM->Get('Kernel::System::Calendar::Team');
            my $UserObject = $Kernel::OM->Get('Kernel::System::User');

            # get allowed team list for current user
            my %TeamList = $TeamObject->AllowedTeamList(
                PreventEmpty => 1,
                UserID       => $Self->{UserID},
            );

            # team names
            my @TeamNames;
            for my $TeamID ( @{$TeamIDs} ) {
                push @TeamNames, $TeamList{$TeamID} if $TeamList{$TeamID};
            }
            if ( scalar @TeamNames ) {
                $Param{TeamNames} = join( '<br>', @TeamNames );
            }
            else {
                $Param{TeamNames} = $Self->{EmptyString};
            }

            # team list string
            $Param{TeamIDStrg} = $LayoutObject->BuildSelection(
                Data         => \%TeamList,
                SelectedID   => $TeamIDs,
                Name         => 'TeamID',
                Multiple     => 1,
                Class        => 'Modernize',
                PossibleNone => 1,
            );

            # iterate through selected teams
            my %TeamUserListAll;
            TEAMID:
            for my $TeamID ( @{$TeamIDs} ) {
                next TEAMID if !$TeamID;

                # get list of team members
                my %TeamUserList = $TeamObject->TeamUserList(
                    TeamID => $TeamID,
                    UserID => $Self->{UserID},
                );

                # get user data
                for my $UserID ( sort keys %TeamUserList ) {
                    my %User = $UserObject->GetUserData(
                        UserID => $UserID,
                    );
                    $TeamUserList{$UserID} = $User{UserFullname};
                }

                %TeamUserListAll = ( %TeamUserListAll, %TeamUserList );
            }

            # resource names
            my @ResourceNames;
            for my $ResourceID ( @{$ResourceIDs} ) {
                push @ResourceNames, $TeamUserListAll{$ResourceID} if $TeamUserListAll{$ResourceID};
            }
            if ( scalar @ResourceNames ) {
                $Param{ResourceNames} = join( '<br>', @ResourceNames );
            }
            else {
                $Param{ResourceNames} = $Self->{EmptyString};
            }

            # team user list string
            $Param{ResourceIDStrg} = $LayoutObject->BuildSelection(
                Data         => \%TeamUserListAll,
                SelectedID   => $ResourceIDs,
                Name         => 'ResourceID',
                Multiple     => 1,
                Class        => 'Modernize',
                PossibleNone => 1,
            );
        }

        my $SelectedRecurrenceType       = 0;
        my $SelectedRecurrenceCustomType = 'CustomDaily';    # default

        if ( $Appointment{Recurring} ) {

            # from appointment
            $SelectedRecurrenceType = $GetParam{RecurrenceType} || $Appointment{RecurrenceType};
            if ( $SelectedRecurrenceType =~ /Custom/ ) {
                $SelectedRecurrenceCustomType = $SelectedRecurrenceType;
                $SelectedRecurrenceType       = 'Custom';
            }
        }

        # recurrence type
        my @RecurrenceTypes = (
            {
                Key   => '0',
                Value => Translatable('Never'),
            },
            {
                Key   => 'Daily',
                Value => Translatable('Every Day'),
            },
            {
                Key   => 'Weekly',
                Value => Translatable('Every Week'),
            },
            {
                Key   => 'Monthly',
                Value => Translatable('Every Month'),
            },
            {
                Key   => 'Yearly',
                Value => Translatable('Every Year'),
            },
            {
                Key   => 'Custom',
                Value => Translatable('Custom'),
            },
        );
        my %RecurrenceTypeLookup = map {
            $_->{Key} => $_->{Value}
        } @RecurrenceTypes;
        $Param{RecurrenceValue} = $LayoutObject->{LanguageObject}->Translate(
            $RecurrenceTypeLookup{$SelectedRecurrenceType},
        );

        # recurrence type selection
        $Param{RecurrenceTypeString} = $LayoutObject->BuildSelection(
            Data         => \@RecurrenceTypes,
            SelectedID   => $SelectedRecurrenceType,
            Name         => 'RecurrenceType',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # recurrence custom type
        my @RecurrenceCustomTypes = (
            {
                Key   => 'CustomDaily',
                Value => Translatable('Daily'),
            },
            {
                Key   => 'CustomWeekly',
                Value => Translatable('Weekly'),
            },
            {
                Key   => 'CustomMonthly',
                Value => Translatable('Monthly'),
            },
            {
                Key   => 'CustomYearly',
                Value => Translatable('Yearly'),
            },
        );
        my %RecurrenceCustomTypeLookup = map {
            $_->{Key} => $_->{Value}
        } @RecurrenceCustomTypes;
        my $RecurrenceCustomType = $RecurrenceCustomTypeLookup{$SelectedRecurrenceCustomType};
        $Param{RecurrenceValue} .= ', ' . $LayoutObject->{LanguageObject}->Translate(
            lc $RecurrenceCustomType,
        ) if $RecurrenceCustomType && $SelectedRecurrenceType eq 'Custom';

        # recurrence custom type selection
        $Param{RecurrenceCustomTypeString} = $LayoutObject->BuildSelection(
            Data       => \@RecurrenceCustomTypes,
            SelectedID => $SelectedRecurrenceCustomType,
            Name       => 'RecurrenceCustomType',
            Class      => 'Modernize',
        );

        # recurrence interval
        my $SelectedInterval = $GetParam{RecurrenceInterval} || $Appointment{RecurrenceInterval} || 1;
        if ( $Appointment{RecurrenceInterval} ) {
            my %RecurrenceIntervalLookup = (
                'CustomDaily' => $LayoutObject->{LanguageObject}->Translate(
                    'day(s)',
                ),
                'CustomWeekly' => $LayoutObject->{LanguageObject}->Translate(
                    'week(s)',
                ),
                'CustomMonthly' => $LayoutObject->{LanguageObject}->Translate(
                    'month(s)',
                ),
                'CustomYearly' => $LayoutObject->{LanguageObject}->Translate(
                    'year(s)',
                ),
            );

            if ( $RecurrenceCustomType && $SelectedRecurrenceType eq 'Custom' ) {
                $Param{RecurrenceValue} .= ', '
                    . $LayoutObject->{LanguageObject}->Translate('every')
                    . ' ' . $Appointment{RecurrenceInterval} . ' '
                    . $RecurrenceIntervalLookup{$SelectedRecurrenceCustomType};
            }
        }

        # add interval selection (1-31)
        my @RecurrenceCustomInterval;
        for ( my $DayNumber = 1; $DayNumber < 32; $DayNumber++ ) {
            push @RecurrenceCustomInterval, {
                Key   => $DayNumber,
                Value => $DayNumber,
            };
        }
        $Param{RecurrenceIntervalString} = $LayoutObject->BuildSelection(
            Data       => \@RecurrenceCustomInterval,
            SelectedID => $SelectedInterval,
            Name       => 'RecurrenceInterval',
        );

        # recurrence limit
        my $RecurrenceLimit = 1;
        if ( $Appointment{RecurrenceCount} ) {
            $RecurrenceLimit = 2;

            if ($SelectedRecurrenceType) {
                $Param{RecurrenceValue} .= ', ' . $LayoutObject->{LanguageObject}->Translate(
                    'for %s time(s)', $Appointment{RecurrenceCount},
                );
            }
        }

        # recurrence limit string
        $Param{RecurrenceLimitString} = $LayoutObject->BuildSelection(
            Data => [
                {
                    Key   => 1,
                    Value => Translatable('until ...'),
                },
                {
                    Key   => 2,
                    Value => Translatable('for ... time(s)'),
                },
            ],
            SelectedID   => $RecurrenceLimit,
            Name         => 'RecurrenceLimit',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        my $RecurrenceUntilDiffTime = 0;
        if ( !$Appointment{RecurrenceUntil} ) {

            # Get current and start time for difference.
            my $SystemTime      = $Kernel::OM->Create('Kernel::System::DateTime')->ToEpoch();
            my $StartTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    Year   => $Appointment{StartYear}   // $GetParam{StartYear},
                    Month  => $Appointment{StartMonth}  // $GetParam{StartMonth},
                    Day    => $Appointment{StartDay}    // $GetParam{StartDay},
                    Hour   => $Appointment{StartHour}   // $GetParam{StartHour},
                    Minute => $Appointment{StartMinute} // $GetParam{StartMinute},
                    Second => 0,
                },
            );
            my $StartTime = $StartTimeObject->ToEpoch();

            $RecurrenceUntilDiffTime = $StartTime - $SystemTime + 60 * 60 * 24 * 3;    # start +3 days
        }
        else {
            $Param{RecurrenceUntil} = sprintf(
                "%04d-%02d-%02d",
                $Appointment{RecurrenceUntilYear},
                $Appointment{RecurrenceUntilMonth},
                $Appointment{RecurrenceUntilDay},
            );

            if ($SelectedRecurrenceType) {
                $Param{RecurrenceValue} .= ', ' . $LayoutObject->{LanguageObject}->Translate(
                    'until %s', $Param{RecurrenceUntil},
                );
            }
        }

        # recurrence until date string
        $Param{RecurrenceUntilString} = $LayoutObject->BuildDateSelection(
            %Appointment,
            %GetParam,
            Prefix                  => 'RecurrenceUntil',
            Format                  => 'DateInputFormat',
            DiffTime                => $RecurrenceUntilDiffTime,
            ValidateDateAfterPrefix => 'Start',
            Validate                => 1,
            YearPeriodPast          => $YearPeriodPast{RecurrenceUntil},
            YearPeriodFuture        => $YearPeriodFuture{RecurrenceUntil},
            OverrideTimeZone        => $OverrideTimeZone,
        );

        # notification template
        my @NotificationTemplates = (
            {
                Key   => '0',
                Value => $LayoutObject->{LanguageObject}->Translate('No notification'),
            },
            {
                Key   => 'Start',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 0 ),
            },
            {
                Key   => '300',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 5 ),
            },
            {
                Key   => '900',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 15 ),
            },
            {
                Key   => '1800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 30 ),
            },
            {
                Key   => '3600',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 1 ),
            },
            {
                Key   => '7200',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 2 ),
            },
            {
                Key   => '43200',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 12 ),
            },
            {
                Key   => '86400',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s day(s) before', 1 ),
            },
            {
                Key   => '172800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s day(s) before', 2 ),
            },
            {
                Key   => '604800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s week before', 1 ),
            },
            {
                Key   => 'Custom',
                Value => $LayoutObject->{LanguageObject}->Translate('Custom'),
            },
        );
        my %NotificationTemplateLookup = map {
            $_->{Key} => $_->{Value}
        } @NotificationTemplates;
        my $SelectedNotificationTemplate = $Appointment{NotificationTemplate} || '0';
        $Param{NotificationValue} = $NotificationTemplateLookup{$SelectedNotificationTemplate};

        # notification selection
        $Param{NotificationStrg} = $LayoutObject->BuildSelection(
            Data         => \@NotificationTemplates,
            SelectedID   => $SelectedNotificationTemplate,
            Name         => 'NotificationTemplate',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # notification custom units
        my @NotificationCustomUnits = (
            {
                Key   => 'minutes',
                Value => $LayoutObject->{LanguageObject}->Translate('minute(s)'),
            },
            {
                Key   => 'hours',
                Value => $LayoutObject->{LanguageObject}->Translate('hour(s)'),
            },
            {
                Key   => 'days',
                Value => $LayoutObject->{LanguageObject}->Translate('day(s)'),
            },
        );
        my %NotificationCustomUnitLookup = map {
            $_->{Key} => $_->{Value}
        } @NotificationCustomUnits;
        my $SelectedNotificationCustomUnit = $Appointment{NotificationCustomRelativeUnit} || 'minutes';

        # notification custom units selection
        $Param{NotificationCustomUnitsStrg} = $LayoutObject->BuildSelection(
            Data         => \@NotificationCustomUnits,
            SelectedID   => $SelectedNotificationCustomUnit,
            Name         => 'NotificationCustomRelativeUnit',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # notification custom units point of time
        my @NotificationCustomUnitsPointOfTime = (
            {
                Key   => 'beforestart',
                Value => $LayoutObject->{LanguageObject}->Translate('before the appointment starts'),
            },
            {
                Key   => 'afterstart',
                Value => $LayoutObject->{LanguageObject}->Translate('after the appointment has been started'),
            },
            {
                Key   => 'beforeend',
                Value => $LayoutObject->{LanguageObject}->Translate('before the appointment ends'),
            },
            {
                Key   => 'afterend',
                Value => $LayoutObject->{LanguageObject}->Translate('after the appointment has been ended'),
            },
        );
        my %NotificationCustomUnitPointOfTimeLookup = map {
            $_->{Key} => $_->{Value}
        } @NotificationCustomUnitsPointOfTime;
        my $SelectedNotificationCustomUnitPointOfTime = $Appointment{NotificationCustomRelativePointOfTime}
            || 'beforestart';

        # notification custom units point of time selection
        $Param{NotificationCustomUnitsPointOfTimeStrg} = $LayoutObject->BuildSelection(
            Data         => \@NotificationCustomUnitsPointOfTime,
            SelectedID   => $SelectedNotificationCustomUnitPointOfTime,
            Name         => 'NotificationCustomRelativePointOfTime',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # Extract the date units for the custom date selection.
        my $NotificationCustomDateTimeSettings = {};
        if ( $Appointment{NotificationCustomDateTime} ) {
            my $NotificationCustomDateTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{NotificationCustomDateTime},
                },
            );
            $NotificationCustomDateTimeSettings = $NotificationCustomDateTimeObject->Get();
        }

        # notification custom date selection
        $Param{NotificationCustomDateTimeStrg} = $LayoutObject->BuildDateSelection(
            Prefix                           => 'NotificationCustomDateTime',
            NotificationCustomDateTimeYear   => $NotificationCustomDateTimeSettings->{Year},
            NotificationCustomDateTimeMonth  => $NotificationCustomDateTimeSettings->{Month},
            NotificationCustomDateTimeDay    => $NotificationCustomDateTimeSettings->{Day},
            NotificationCustomDateTimeHour   => $NotificationCustomDateTimeSettings->{Hour},
            NotificationCustomDateTimeMinute => $NotificationCustomDateTimeSettings->{Minute},
            Format                           => 'DateInputFormatLong',
            YearPeriodPast                   => $YearPeriodPast{Start},
            YearPeriodFuture                 => $YearPeriodFuture{Start},
        );

        # prepare radio button for custom date time and relative input
        $Appointment{NotificationCustom} ||= '';

        if ( $Appointment{NotificationCustom} eq 'datetime' ) {
            $Param{NotificationCustomDateTimeInputRadio} = 'checked ';
        }
        elsif ( $Appointment{NotificationCustom} eq 'relative' ) {
            $Param{NotificationCustomRelativeInputRadio} = 'checked ';
        }
        else {
            $Param{NotificationCustomRelativeInputRadio} = 'checked ';
        }

        # notification custom string value
        if ( $Appointment{NotificationCustom} eq 'datetime' ) {
            $Param{NotificationValue} .= ', ' . $LayoutObject->{LanguageObject}->FormatTimeString(
                $Appointment{NotificationCustomDateTime},
                'DateFormat'
            );
        }
        elsif ( $Appointment{NotificationCustom} eq 'relative' ) {
            if (
                $Appointment{NotificationCustomRelativeUnit}
                && $Appointment{NotificationCustomRelativePointOfTime}
                )
            {
                $Appointment{NotificationCustomRelativeUnitCount} ||= 0;
                $Param{NotificationValue} .= ', '
                    . $Appointment{NotificationCustomRelativeUnitCount}
                    . ' '
                    . $NotificationCustomUnitLookup{$SelectedNotificationCustomUnit}
                    . ' '
                    . $NotificationCustomUnitPointOfTimeLookup{$SelectedNotificationCustomUnitPointOfTime};
            }
        }

# RotherOSS / AppointmentToTicket
        my %FutureTask;
        if ( %Appointment ) {
            my $TaskID;
            if ( $Appointment{FutureTaskID} ) {
                $TaskID = $Appointment{FutureTaskID};
            }
            # Only for parent appointments
            elsif ( $Appointment{Recurring} ) {
                # Check all appointments of series for future task id
                my @AppointmentList = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentList(
                    CalendarID => $Appointment{CalendarID},
                    ParentID => $Appointment{AppointmentID},
                );
                my %ParentAppointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet( AppointmentID => $Appointment{AppointmentID} );
                unshift @AppointmentList, \%ParentAppointment;

                APPOINTMENTLIST:
                for my $RecurringAppointment (@AppointmentList) {
                    if ( $RecurringAppointment->{FutureTaskID} ) {
                        $TaskID = $RecurringAppointment->{FutureTaskID};
                        last APPOINTMENTLIST;
                    }
                }
            }
            if ( $TaskID ) {
                %FutureTask = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB')->FutureTaskGet(
                    TaskID => $TaskID,
                );
            }
        }
        # ticket template
        my @TicketTemplates = (
            {
                Key   => '0',
                Value => $LayoutObject->{LanguageObject}->Translate('No ticket creation'),
            },
            {
                Key   => 'Start',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 0 ),
            },
            {
                Key   => '300',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 5 ),
            },
            {
                Key   => '900',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 15 ),
            },
            {
                Key   => '1800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s minute(s) before', 30 ),
            },
            {
                Key   => '3600',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 1 ),
            },
            {
                Key   => '7200',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 2 ),
            },
            {
                Key   => '43200',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s hour(s) before', 12 ),
            },
            {
                Key   => '86400',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s day(s) before', 1 ),
            },
            {
                Key   => '172800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s day(s) before', 2 ),
            },
            {
                Key   => '604800',
                Value => $LayoutObject->{LanguageObject}->Translate( '%s week before', 1 ),
            },
            {
                Key   => 'Custom',
                Value => $LayoutObject->{LanguageObject}->Translate('Custom'),
            },
        );
        my %TicketTemplateLookup = map {
            $_->{Key} => $_->{Value}
        } @TicketTemplates;

        my $SelectedTicketTemplate = defined $FutureTask{Data} ? $FutureTask{Data}->{AppointmentTicket}->{Template} : '0';
        $Param{TicketValue} = $TicketTemplateLookup{$SelectedTicketTemplate};

        # ticket selection
        $Param{TicketStrg} = $LayoutObject->BuildSelection(
            Data         => \@TicketTemplates,
            SelectedID   => $SelectedTicketTemplate,
            Name         => 'TicketTemplate',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # ticket custom units
        my @TicketCustomUnits = (
            {
                Key   => 'minutes',
                Value => $LayoutObject->{LanguageObject}->Translate('minute(s)'),
            },
            {
                Key   => 'hours',
                Value => $LayoutObject->{LanguageObject}->Translate('hour(s)'),
            },
            {
                Key   => 'days',
                Value => $LayoutObject->{LanguageObject}->Translate('day(s)'),
            },
        );
        my %TicketCustomUnitLookup = map {
            $_->{Key} => $_->{Value}
        } @TicketCustomUnits;
        my $SelectedTicketCustomUnit = ( $FutureTask{Data} ? $FutureTask{Data}->{AppointmentTicket}->{CustomRelativeUnit} : '' ) || 'minutes';

        # ticket custom units selection
        $Param{TicketCustomUnitsStrg} = $LayoutObject->BuildSelection(
            Data         => \@TicketCustomUnits,
            SelectedID   => $SelectedTicketCustomUnit,
            Name         => 'TicketCustomRelativeUnit',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # ticket custom units point of time
        my @TicketCustomUnitsPointOfTime = (
            {
                Key   => 'beforestart',
                Value => $LayoutObject->{LanguageObject}->Translate('before the appointment starts'),
            },
            {
                Key   => 'afterstart',
                Value => $LayoutObject->{LanguageObject}->Translate('after the appointment has been started'),
            },
            {
                Key   => 'beforeend',
                Value => $LayoutObject->{LanguageObject}->Translate('before the appointment ends'),
            },
            {
                Key   => 'afterend',
                Value => $LayoutObject->{LanguageObject}->Translate('after the appointment has been ended'),
            },
        );
        my %TicketCustomUnitPointOfTimeLookup = map {
            $_->{Key} => $_->{Value}
        } @TicketCustomUnitsPointOfTime;
        my $SelectedTicketCustomUnitPointOfTime = ( $FutureTask{Data} ? $FutureTask{Data}->{AppointmentTicket}->{CustomRelativePointOfTime} : '' )
            || 'beforestart';

        # ticket custom units point of time selection
        $Param{TicketCustomUnitsPointOfTimeStrg} = $LayoutObject->BuildSelection(
            Data         => \@TicketCustomUnitsPointOfTime,
            SelectedID   => $SelectedTicketCustomUnitPointOfTime,
            Name         => 'TicketCustomRelativePointOfTime',
            Multiple     => 0,
            Class        => 'Modernize',
            PossibleNone => 0,
        );

        # Extract the date units for the custom date selection.
        my $TicketCustomDateTimeSettings = {};
        if ( $FutureTask{Data} && $FutureTask{Data}->{AppointmentTicket}->{CustomDateTime} ) {
            my $TicketCustomDateTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $FutureTask{Data}->{AppointmentTicket}->{CustomDateTime},
                },
            );
            $TicketCustomDateTimeSettings = $TicketCustomDateTimeObject->Get();
        }

        # ticket custom date selection
        $Param{TicketCustomDateTimeStrg} = $LayoutObject->BuildDateSelection(
            Prefix                           => 'TicketCustomDateTime',
            TicketCustomDateTimeYear   => $TicketCustomDateTimeSettings->{Year},
            TicketCustomDateTimeMonth  => $TicketCustomDateTimeSettings->{Month},
            TicketCustomDateTimeDay    => $TicketCustomDateTimeSettings->{Day},
            TicketCustomDateTimeHour   => $TicketCustomDateTimeSettings->{Hour},
            TicketCustomDateTimeMinute => $TicketCustomDateTimeSettings->{Minute},
            Format                           => 'DateInputFormatLong',
            YearPeriodPast                   => $YearPeriodPast{Start},
            YearPeriodFuture                 => $YearPeriodFuture{Start},
        );

        # prepare radio button for custom date time and relative input
        if ( $FutureTask{Data} ) {
            $FutureTask{Data}->{AppointmentTicket}->{Custom} ||= '';
        }

        if ( $FutureTask{Data} && $FutureTask{Data}->{AppointmentTicket}->{Custom} eq 'datetime' ) {
            $Param{TicketCustomDateTimeInputRadio} = 'checked="checked"';
        }
        elsif ( $FutureTask{Data} && $FutureTask{Data}->{AppointmentTicket}->{Custom} eq 'relative' ) {
            $Param{TicketCustomRelativeInputRadio} = 'checked="checked"';
        }
        else {
            $Param{TicketCustomRelativeInputRadio} = 'checked="checked"';
        }

        # ticket custom string value
        if ( $FutureTask{Data} && $FutureTask{Data}->{AppointmentTicket}->{Custom} eq 'datetime' ) {
            $Param{TicketValue} .= ', ' . $LayoutObject->{LanguageObject}->FormatTimeString(
                $FutureTask{Data}->{AppointmentTicket}->{CustomDateTime},
                'DateFormat'
            );
        }
        elsif ( $FutureTask{Data} && $FutureTask{Data}->{AppointmentTicket}->{Custom} eq 'relative' ) {
            if (
                $FutureTask{Data}->{AppointmentTicket}->{CustomRelativeUnit}
                && $FutureTask{Data}->{AppointmentTicket}->{CustomRelativePointOfTime}
                )
            {
                $FutureTask{Data}->{AppointmentTicket}->{CustomRelativeUnitCount} ||= 0;
                $Param{TicketValue} .= ', '
                    . $FutureTask{Data}->{AppointmentTicket}->{CustomRelativeUnitCount}
                    . ' '
                    . $TicketCustomUnitLookup{$SelectedTicketCustomUnit}
                    . ' '
                    . $TicketCustomUnitPointOfTimeLookup{$SelectedTicketCustomUnitPointOfTime};
            }
        }
# EO AppointmentToTicket

        # get plugin list
        $Param{PluginList} = $PluginObject->PluginList();

        # new appointment plugin search
        if ( $GetParam{PluginKey} && ( $GetParam{Search} || $GetParam{ObjectID} ) ) {

            if ( grep { $_ eq $GetParam{PluginKey} } keys %{ $Param{PluginList} } ) {

                # search using plugin
                my $ResultList = $PluginObject->PluginSearch(
                    %GetParam,
                    UserID => $Self->{UserID},
                );

                $Param{PluginData}->{ $GetParam{PluginKey} } = [];
                my @LinkArray = sort keys %{$ResultList};

                # add possible links
                for my $LinkID (@LinkArray) {
                    push @{ $Param{PluginData}->{ $GetParam{PluginKey} } }, {
                        LinkID   => $LinkID,
                        LinkName => $ResultList->{$LinkID},
                        LinkURL  => sprintf(
                            $Param{PluginList}->{ $GetParam{PluginKey} }->{PluginURL},
                            $LinkID
                        ),
                    };
                }

                $Param{PluginList}->{ $GetParam{PluginKey} }->{LinkList} = $LayoutObject->JSONEncode(
                    Data => \@LinkArray,
                );
            }
        }

        # edit appointment plugin links
        elsif ( $GetParam{AppointmentID} ) {

            for my $PluginKey ( sort keys %{ $Param{PluginList} } ) {
                my $LinkList = $PluginObject->PluginLinkList(
                    AppointmentID => $GetParam{AppointmentID},
                    PluginKey     => $PluginKey,
                    UserID        => $Self->{UserID},
                );
                my @LinkArray;

                $Param{PluginData}->{$PluginKey} = [];
                for my $LinkID ( sort keys %{$LinkList} ) {
                    push @{ $Param{PluginData}->{$PluginKey} }, $LinkList->{$LinkID};
                    push @LinkArray,                            $LinkList->{$LinkID}->{LinkID};
                }

                $Param{PluginList}->{$PluginKey}->{LinkList} = $LayoutObject->JSONEncode(
                    Data => \@LinkArray,
                );
            }
        }

# RotherOSS / AppointmentToTicket
#         # html mask output
#         $LayoutObject->Block(
#             Name => 'EditMask',
#             Data => {
#                 %Param,
#                 %GetParam,
#                 %Appointment,
#                 PermissionLevel => $PermissionLevel{$Permissions},
#             },
#         );

        # Build ticket fields
        # frontend specific config
        my %UserPreferences = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
            UserID => $Self->{UserID},
        );

        # Fetch dynamic field configs
        my @DynamicFieldConfigs;
        if ( defined $Config->{DynamicField} ) {
            my $DynamicFieldConfigsRef = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
                Valid       => 1,
                ObjectType  => [ 'Ticket', 'Article' ],
                FieldFilter => $Config->{DynamicField} || {},
            );
            @DynamicFieldConfigs = defined $DynamicFieldConfigsRef ? @{ $DynamicFieldConfigsRef } : ();
        }

        if ( $GetParam{Dest} ) {
            $GetParam{Queue} = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( QueueID => $GetParam{Dest} );
            $GetParam{QueueID} = $GetParam{Dest};
        }
        elsif ( %FutureTask ) {
            $GetParam{QueueID} = $FutureTask{Data}->{AppointmentTicket}->{QueueID};
            $GetParam{Queue} = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( QueueID => $GetParam{QueueID} );
            $GetParam{NextStateID} = $FutureTask{Data}->{AppointmentTicket}->{StateID};
            $GetParam{TypeID} = $FutureTask{Data}->{AppointmentTicket}->{TypeID};
            $GetParam{ServiceID} = $FutureTask{Data}->{AppointmentTicket}->{ServiceID};
            $GetParam{SLAID} = $FutureTask{Data}->{AppointmentTicket}->{SLAID};
        }
        else {
            my $UserDefaultQueue = $ConfigObject->Get('Ticket::Frontend::UserDefaultQueue') || '';

            if ($UserDefaultQueue) {
                $GetParam{QueueID} = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => $UserDefaultQueue );
                if ( $GetParam{QueueID} ) {
                    $GetParam{Queue} = "$GetParam{TicketQueueID}||$UserDefaultQueue";
                }
            }
        }

        my %DynamicFieldValues;
        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @DynamicFieldConfigs ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # extract the dynamic field value from the web request
            $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ParamObject        => $ParamObject,
                LayoutObject       => $LayoutObject,
            );

            if ( !$DynamicFieldValues{ $DynamicFieldConfig->{Name} } ) {
                # extract the dynamic field value from the web request with approach for array
                $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
                    DynamicFieldConfig => { $DynamicFieldConfig->%*, Name => $DynamicFieldConfig->{Name} . '[]' },
                    ParamObject        => $ParamObject,
                    LayoutObject       => $LayoutObject,
                );
            }
        }

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @DynamicFieldConfigs ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfig->{Config} );
            next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

            # to store dynamic field value from database (or undefined)
            my $Value;

            # Check if the user has a user specific default value for
            # the dynamic field, otherwise will use Dynamic Field default value
            # get default value from dynamic field config (if any)
            $Value = $DynamicFieldConfig->{Config}->{DefaultValue} || '';

            # override the value from user preferences if is set
            if ( $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} } ) {
                $Value = $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} };
            }

            if ( $DynamicFieldValues{$DynamicFieldConfig->{Name}} ) {
                $Value = $DynamicFieldValues{$DynamicFieldConfig->{Name}};
            }

            if ( %FutureTask && $FutureTask{Data}->{AppointmentTicket}->{DynamicFields}->{$DynamicFieldConfig->{Name}} ) {
                $Value = $FutureTask{Data}->{AppointmentTicket}->{DynamicFields}->{$DynamicFieldConfig->{Name}};
            }

            $GetParam{DynamicField}{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $Value;
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTMLData;
        DYNAMICFIELD:
        for my $i ( 0 .. $#DynamicFieldConfigs ) {
            next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfigs[$i] );

            my $DynamicFieldConfig = $DynamicFieldConfigs[$i];

            # get field html
            $DynamicFieldHTMLData{ $DynamicFieldConfig->{FieldOrder} } = $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                Value           => $GetParam{DynamicField}{"DynamicField_$DynamicFieldConfig->{Name}"},
                LayoutObject    => $LayoutObject,
                ParamObject     => $ParamObject,
                AJAXUpdate      => 1,
                Mandatory       => $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
            );
        }
        my @DynamicFieldHTML;
        for my $Key (sort { $a <=> $b } keys %DynamicFieldHTMLData) {
            push @DynamicFieldHTML, $DynamicFieldHTMLData{$Key};
        }

        # get list type
        my $TreeView = 0;
        if ( $ConfigObject->Get('Ticket::Frontend::ListType') eq 'tree' ) {
            $TreeView = 1;
        }

        # if future task exists, transform existing data into neede structure
        if (%FutureTask) {
            my @CustomerUserStrings = split /,/, $FutureTask{Data}->{AppointmentTicket}->{CustomerUser};
            if ( @CustomerUserStrings ) {
                my $Count = 1;
                for my $CustomerUserString ( @CustomerUserStrings ) {
                    my %CustomerUser = $CustomerUserObject->CustomerUserDataGet(
                        User => $CustomerUserString,
                    );
                    if ( %CustomerUser ) {
                        push @MultipleCustomer, {
                            Count => $Count++,
                            CustomerElement => '"' . $CustomerUser{UserFirstname} . ' ' . $CustomerUser{UserLastname} . '" <' . $CustomerUser{UserEmail} . '>',
                            CustomerSelected => ( $FutureTask{Data}->{AppointmentTicket}->{SelectedCustomerUser} eq $CustomerUserString ? 'checked="checked"' : '' ),
                            CustomerKey => $CustomerUser{UserLogin},
                            CustomerError => '',
                            CustomerErrorMsg => 'CustomerGenericServerErrorMsg',
                            CustomerDisabled => '',
                        }
                    }
                    else {
                        push @MultipleCustomer, {
                            Count => $Count++,
                            CustomerElement => $CustomerUserString,
                            CustomerSelected => ( $FutureTask{Data}->{AppointmentTicket}->{SelectedCustomerUser} eq $CustomerUserString ? 'checked="checked"' : '' ),
                            CustomerError => '',
                            CustomerErrrorMsg => 'CustomerGenericServerErrorMsg',
                            CustomerDisabled => '',
                        }
                    }
                }
            }
            $GetParam{SelectedCustomerUser} = $FutureTask{Data}->{AppointmentTicket}->{SelectedCustomerUser};
        }


        # for each standard field which has to be checked, run the defined method
        my $QueueValues = $Self->_GetTos(
            %GetParam,
        );

        my $PriorityValues = $Self->_GetPriorities(
            %GetParam,
        );

        my $StateValues = $Self->_GetStates(
            %GetParam,
        );

        my $TypeValues = $Self->_GetTypes(
            %GetParam,
        );

        my $ServiceValues = $Self->_GetServices(
            %GetParam,
        );

        my $SLAValues = $Self->_GetSLAs(
            %GetParam,
        );

        # Build queue html string
        my $QueueHTMLString;
        if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') eq 'Queue' ) {
            $QueueHTMLString = $LayoutObject->AgentQueueListOption(
                Class          => 'Mandatory Validate_Required Modernize',
                Data           => $QueueValues,
                Multiple       => 0,
                Size           => 0,
                Name           => 'Dest',
                TreeView       => $TreeView,
                SelectedID     => $GetParam{QueueID},
                Translation    => 0,
                OnChangeSubmit => 0,
                Mandatory      => 1,
            );
        }
        else {
            $QueueHTMLString = $LayoutObject->BuildSelection(
                Class          => 'Mandatory Validate_Required Modernize',
                Data           => $QueueValues,
                Multiple       => 0,
                Size           => 0,
                Name           => 'Dest',
                TreeView       => $TreeView,
                SelectedID     => $GetParam{QueueID},
                Translation    => 0,
                OnChangeSubmit => 0,
                Mandatory      => 1,
            );
        }

        # build type string
        my $TypeHTMLString;
        if ( $ConfigObject->Get('Ticket::Type') ) {
            $TypeHTMLString = $LayoutObject->BuildSelection(
                Class        => 'Modernize Validate_Required' . ( $Param{Errors}->{TypeIDInvalid} || ' ' ),
                Data         => $TypeValues,
                Name         => 'TypeID',
                SelectedID   => $GetParam{TypeID},
                PossibleNone => 1,
                Sort         => 'AlphanumericValue',
                Translation  => 1,
                Mandatory    => 1,
            );
        }

        # build state string
        my $StateHTMLString = $LayoutObject->BuildSelection(
            Class        => 'Modernize Validate_Required',
            Data         => $StateValues,
            Name         => 'NextStateID',
            SelectedID   => $GetParam{NextStateID} || $Config->{StateDefault},
            SelectedValue => $GetParam{NextStateID} || $Config->{StateDefault},
            PossibleNone => 1,
            Sort         => 'AlphanumericValue',
            Translation  => 1,
            Mandatory    => 1,
        );

        # build service and SLA string
        my $ServiceHTMLString;
        my $SLAHTMLString;
        if ( $ConfigObject->Get('Ticket::Service') ) {
            $ServiceHTMLString = $LayoutObject->BuildSelection(
                Class => 'Modernize '
                    . ( $Config->{ServiceMandatory} ? 'Validate_Required ' : '' )
                    . ( $Param{Errors}->{ServiceIDInvalid} || '' ),
                Data         => $ServiceValues,
                Name         => 'ServiceID',
                SelectedID   => $GetParam{ServiceID},
                PossibleNone => 1,
                TreeView     => $TreeView,
                Sort         => 'TreeView',
                Translation  => 1,
            );
            $SLAHTMLString = $LayoutObject->BuildSelection(
                Class      => 'Modernize '
                    . ( $Config->{SLAMandatory} ? 'Validate_Required ' : '' )
                    . ( $Param{Errors}->{SLAInvalid} || '' ),
                Data         => $SLAValues,
                Name         => 'SLAID',
                SelectedID   => $GetParam{SLAID},
                PossibleNone => 1,
                Sort         => 'AlphanumericValue',
                Translation  => 1,
            );
        }



        # get priority data
        if ( !$GetParam{Priority} ) {
            $GetParam{Priority} = $Config->{Priority};
        }
        if ( %FutureTask ) {
            $GetParam{PriorityID} = $FutureTask{Data}->{AppointmentTicket}->{PriorityID};
        }

        # build priority html string
        my $PriorityHTMLString;
        if ( $Config->{Priority} ) {
            $PriorityHTMLString = $LayoutObject->BuildSelection(
                Class         => 'Validate_Required Modernize',
                Data          => $PriorityValues,
                Name          => 'PriorityID',
                SelectedID    => $GetParam{PriorityID},
                SelectedValue => $GetParam{Priority},
                Translation   => 1,
                Mandatory     => 1,
            );
        }

        $Param{CustomerHiddenContainer} = $#MultipleCustomer != -1 ? '' : 'Hidden';
        $Param{ArticleVisibleForCustomer} = ($Param{TicketArticleVisibleForCustomer} || ( %FutureTask && $FutureTask{Data}->{AppointmentTicket}->{ArticleVisibleForCustomer})) ? 'checked=checked' : '';

        if ( %FutureTask ) {
            # html mask output
            $LayoutObject->Block(
                Name => 'EditMask',
                Data => {
                    %{$FutureTask{Data} || \{}},
                    %Param,
                    %GetParam,
                    %Appointment,
                    PermissionLevel => $PermissionLevel{$Permissions},
                    QueueHTMLString => $QueueHTMLString,
                    PriorityHTMLString => $PriorityHTMLString,
                    TypeHTMLString => $TypeHTMLString,
                    StateHTMLString => $StateHTMLString,
                    ServiceHTMLString => $ServiceHTMLString,
                    ServiceMandatory => $Config->{ServiceMandatory} || 0,
                    SLAHTMLString => $SLAHTMLString,
                    SLAMandatory => $Config->{SLAMandatory} || 0,
                    DynamicFieldHTML => \@DynamicFieldHTML,
                },
            );
        }
        else {
            # html mask output
            $LayoutObject->Block(
                Name => 'EditMask',
                Data => {
                    %Param,
                    %GetParam,
                    %Appointment,
                    PermissionLevel => $PermissionLevel{$Permissions},
                    QueueHTMLString => $QueueHTMLString,
                    PriorityHTMLString => $PriorityHTMLString,
                    TypeHTMLString => $TypeHTMLString,
                    StateHTMLString => $StateHTMLString,
                    ServiceHTMLString => $ServiceHTMLString,
                    ServiceMandatory => $Config->{ServiceMandatory} || 0,
                    SLAHTMLString => $SLAHTMLString,
                    SLAMandatory => $Config->{SLAMandatory} || 0,
                    DynamicFieldHTML => \@DynamicFieldHTML,
               },
            );
        }

        my $CustomerCounter = 0;
        if ( @MultipleCustomer ) {
            for my $Item ( @MultipleCustomer ) {
                # set empty values for errors
                $Item->{CustomerError}    = '';
                $Item->{CustomerDisabled} = '';
                $Item->{CustomerErrorMsg} = 'CustomerGenericServerErrorMsg';

                $LayoutObject->Block(
                    Name => 'MultipleCustomer',
                    Data => $Item,
                );
                $LayoutObject->Block(
                    Name => $Item->{CustomerErrorMsg},
                    Data => $Item,
                );
                if ( $Item->{CustomerError} ) {
                    $LayoutObject->Block(
                        Name => 'CustomerErrorExplantion',
                    );
                }
                $CustomerCounter++;
            }
        }

        if ( !$CustomerCounter ) {
            $Param{CustomerHiddenContainer} = 'Hidden';
        }

        $LayoutObject->Block(
            Name => 'MultipleCustomerCounter',
            Data => {
                CustomerCounter => $CustomerCounter++,
            },
        );
# EO AppointmentToTicket

        $LayoutObject->AddJSData(
            Key   => 'CalendarPermissionLevel',
            Value => $PermissionLevel{$Permissions},
        );
        $LayoutObject->AddJSData(
            Key   => 'EditAppointmentID',
            Value => $Appointment{AppointmentID} // '',
        );
        $LayoutObject->AddJSData(
            Key   => 'EditParentID',
            Value => $Appointment{ParentID} // '',
        );

        # get registered location links
        my $LocationLinkConfig = $ConfigObject->Get('AgentAppointmentEdit::Location::Link') // {};
        for my $ConfigKey ( sort keys %{$LocationLinkConfig} ) {

            # show link icon
            $LayoutObject->Block(
                Name => 'LocationLink',
                Data => {
                    Location => $Appointment{Location} // '',
                    %{ $LocationLinkConfig->{$ConfigKey} },
                },
            );
        }

        my $Output = $LayoutObject->Output(
            TemplateFile => 'AgentAppointmentEdit',
            Data         => {
                %Param,
                %GetParam,
                %Appointment,
            },
            AJAX => 1,
        );
        return $LayoutObject->Attachment(
            NoCache     => 1,
            ContentType => 'text/html',
            Charset     => $LayoutObject->{UserCharset},
            Content     => $Output,
            Type        => 'inline',
        );
    }

    # ------------------------------------------------------------ #
    # add/edit appointment
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'EditAppointment' ) {

# RotherOSS / AppointmentToTicket
        if ($GetParam{TicketTemplate}) {
            # Validate incoming values
            my $QueueValues = $Self->_GetTos(
                %GetParam,
            );
            if ( !$QueueValues->{$GetParam{Dest}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field dest!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );
            }

            my $StateValues = $Self->_GetStates(
                %GetParam,
            );
            if ( !$StateValues->{$GetParam{NextStateID}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field next state!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );

            }

            my $ServiceValues = $Self->_GetServices(
                %GetParam,
            );
            if ( $ConfigObject->Get('Ticket::Service') && ($GetParam{ServiceID} || $Config->{ServiceMandatory}) && !$ServiceValues->{$GetParam{ServiceID}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field service!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );

            }

            my $SLAValues = $Self->_GetSLAs(
                %GetParam,
            );
            if ( $ConfigObject->Get('Ticket::Service') && ($GetParam{SLAID} || $Config->{SLAMandatory}) && !$SLAValues->{$GetParam{SLAID}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field SLA!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );

            }

            my $TypeValues = $Self->_GetTypes(
                %GetParam,
            );
            if ( $ConfigObject->Get('Ticket::Type') &&  !$TypeValues->{$GetParam{TypeID}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field type!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );

            }

            my $PriorityValues = $Self->_GetPriorities(
                %GetParam,
            );
            if ( !$PriorityValues->{$GetParam{PriorityID}} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field priority!' ),
                    Comment => Translatable('Please contact the administrator.'),
                );

            }
        }
# EO AppointmentTicket

        my %Appointment;

        if ( $GetParam{AppointmentID} ) {
            %Appointment = $AppointmentObject->AppointmentGet(
                AppointmentID => $GetParam{AppointmentID},
            );

            # check permissions
            $Permissions = $CalendarObject->CalendarPermissionGet(
                CalendarID => $Appointment{CalendarID},
                UserID     => $Self->{UserID},
            );

            my $RequiredPermission = 2;
            if ( $GetParam{CalendarID} && $GetParam{CalendarID} != $Appointment{CalendarID} ) {

                # in order to move appointment to another calendar, user needs "create" permission
                $RequiredPermission = 3;
            }

            if ( $PermissionLevel{$Permissions} < $RequiredPermission ) {

                # no permission

                # build JSON output
                $JSON = $LayoutObject->JSONEncode(
                    Data => {
                        Success => 0,
                        Error   => Translatable('No permission!'),
                    },
                );

                # send JSON response
                return $LayoutObject->Attachment(
                    ContentType => 'application/json',
                    Content     => $JSON,
                    Type        => 'inline',
                    NoCache     => 1,
                );
            }
        }

        if ( $GetParam{AllDay} ) {
            $GetParam{StartTime} = sprintf(
                "%04d-%02d-%02d 00:00:00",
                $GetParam{StartYear}, $GetParam{StartMonth}, $GetParam{StartDay}
            );
            $GetParam{EndTime} = sprintf(
                "%04d-%02d-%02d 00:00:00",
                $GetParam{EndYear}, $GetParam{EndMonth}, $GetParam{EndDay}
            );

            my $StartTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $GetParam{StartTime},
                },
            );
            my $EndTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $GetParam{EndTime},
                },
            );

            # Prevent storing end time before start time.
            if ( $EndTimeObject < $StartTimeObject ) {
                $EndTimeObject = $StartTimeObject->Clone();
            }

            # Make end time inclusive, add whole day.
            $EndTimeObject->Add(
                Days => 1,
            );
            $GetParam{EndTime} = $EndTimeObject->ToString();
        }
        elsif ( $GetParam{Recurring} && $GetParam{UpdateType} && $GetParam{UpdateDelta} ) {

            my $StartTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{StartTime},
                },
            );
            my $EndTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{EndTime},
                },
            );

            # Calculate new start/end times.
            if ( $GetParam{UpdateType} eq 'StartTime' ) {
                $StartTimeObject->Add(
                    Seconds => $GetParam{UpdateDelta},
                );
                $GetParam{StartTime} = $StartTimeObject->ToString();
            }
            elsif ( $GetParam{UpdateType} eq 'EndTime' ) {
                $EndTimeObject->Add(
                    Seconds => $GetParam{UpdateDelta},
                );
                $GetParam{EndTime} = $EndTimeObject->ToString();
            }
            else {
                $StartTimeObject->Add(
                    Seconds => $GetParam{UpdateDelta},
                );
                $EndTimeObject->Add(
                    Seconds => $GetParam{UpdateDelta},
                );
                $GetParam{StartTime} = $StartTimeObject->ToString();
                $GetParam{EndTime}   = $EndTimeObject->ToString();
            }
        }
        else {
            if (
                defined $GetParam{StartYear}
                && defined $GetParam{StartMonth}
                && defined $GetParam{StartDay}
                && defined $GetParam{StartHour}
                && defined $GetParam{StartMinute}
                )
            {
                $GetParam{StartTime} = sprintf(
                    "%04d-%02d-%02d %02d:%02d:00",
                    $GetParam{StartYear}, $GetParam{StartMonth}, $GetParam{StartDay},
                    $GetParam{StartHour}, $GetParam{StartMinute}
                );

                # Convert start time to local time.
                my $StartTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String   => $GetParam{StartTime},
                        TimeZone => $Self->{UserTimeZone},
                    },
                );
                if ( $Self->{UserTimeZone} ) {
                    $StartTimeObject->ToOTOBOTimeZone();
                }
                $GetParam{StartTime} = $StartTimeObject->ToString();
            }
            else {
                $GetParam{StartTime} = $Appointment{StartTime};
            }

            if (
                defined $GetParam{EndYear}
                && defined $GetParam{EndMonth}
                && defined $GetParam{EndDay}
                && defined $GetParam{EndHour}
                && defined $GetParam{EndMinute}
                )
            {
                $GetParam{EndTime} = sprintf(
                    "%04d-%02d-%02d %02d:%02d:00",
                    $GetParam{EndYear}, $GetParam{EndMonth}, $GetParam{EndDay},
                    $GetParam{EndHour}, $GetParam{EndMinute}
                );

                # Convert end time to local time.
                my $EndTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String   => $GetParam{EndTime},
                        TimeZone => $Self->{UserTimeZone},
                    },
                );
                if ( $Self->{UserTimeZone} ) {
                    $EndTimeObject->ToOTOBOTimeZone();
                }

                # Get already calculated local start time.
                my $StartTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $GetParam{StartTime},
                    },
                );

                # Prevent storing end time before start time.
                if ( $EndTimeObject < $StartTimeObject ) {
                    $EndTimeObject = $StartTimeObject->Clone();
                }

                $GetParam{EndTime} = $EndTimeObject->ToString();
            }
            else {
                $GetParam{EndTime} = $Appointment{EndTime};
            }
        }

        # Prevent recurrence until dates before start time.
        if ( $Appointment{Recurring} && $Appointment{RecurrenceUntil} ) {
            my $StartTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $GetParam{StartTime},
                },
            );
            my $RecurrenceUntilObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Appointment{RecurrenceUntil},
                },
            );
            if ( $RecurrenceUntilObject < $StartTimeObject ) {
                $Appointment{RecurrenceUntil} = $GetParam{StartTime};
            }
        }

        # recurring appointment
        if ( $GetParam{Recurring} && $GetParam{RecurrenceType} ) {

            if (
                $GetParam{RecurrenceType} eq 'Daily'
                || $GetParam{RecurrenceType} eq 'Weekly'
                || $GetParam{RecurrenceType} eq 'Monthly'
                || $GetParam{RecurrenceType} eq 'Yearly'
                )
            {
                $GetParam{RecurrenceInterval} = 1;
            }
            elsif ( $GetParam{RecurrenceType} eq 'Custom' ) {

                if ( $GetParam{RecurrenceCustomType} eq 'CustomWeekly' ) {
                    if ( $GetParam{Days} ) {
                        my @Days = split /,/, $GetParam{Days};
                        $GetParam{RecurrenceFrequency} = \@Days;
                    }
                    else {
                        my $StartTimeObject = $Kernel::OM->Create(
                            'Kernel::System::DateTime',
                            ObjectParams => {
                                String => $GetParam{StartTime},
                            },
                        );
                        my $StartTimeSettings = $StartTimeObject->Get();
                        $GetParam{RecurrenceFrequency} = [ $StartTimeSettings->{DayOfWeek} ];
                    }
                }
                elsif ( $GetParam{RecurrenceCustomType} eq 'CustomMonthly' ) {
                    if ( $GetParam{MonthDays} ) {
                        my @MonthDays = split /,/, $GetParam{MonthDays};
                        $GetParam{RecurrenceFrequency} = \@MonthDays;
                    }
                    else {
                        my $StartTimeObject = $Kernel::OM->Create(
                            'Kernel::System::DateTime',
                            ObjectParams => {
                                String => $GetParam{StartTime},
                            },
                        );
                        my $StartTimeSettings = $StartTimeObject->Get();
                        $GetParam{RecurrenceFrequency} = [ $StartTimeSettings->{Day} ];
                    }
                }
                elsif ( $GetParam{RecurrenceCustomType} eq 'CustomYearly' ) {
                    if ( $GetParam{Months} ) {
                        my @Months = split /,/, $GetParam{Months};
                        $GetParam{RecurrenceFrequency} = \@Months;
                    }
                    else {
                        my $StartTimeObject = $Kernel::OM->Create(
                            'Kernel::System::DateTime',
                            ObjectParams => {
                                String => $GetParam{StartTime},
                            },
                        );
                        my $StartTimeSettings = $StartTimeObject->Get();
                        $GetParam{RecurrenceFrequency} = [ $StartTimeSettings->{Month} ];
                    }
                }

                $GetParam{RecurrenceType} = $GetParam{RecurrenceCustomType};
            }

            # until ...
            if (
                $GetParam{RecurrenceLimit} eq '1'
                && $GetParam{RecurrenceUntilYear}
                && $GetParam{RecurrenceUntilMonth}
                && $GetParam{RecurrenceUntilDay}
                )
            {
                $GetParam{RecurrenceUntil} = sprintf(
                    "%04d-%02d-%02d 00:00:00",
                    $GetParam{RecurrenceUntilYear}, $GetParam{RecurrenceUntilMonth},
                    $GetParam{RecurrenceUntilDay}
                );

                # Prevent recurrence until dates before start time.
                my $StartTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $GetParam{StartTime},
                    },
                );
                my $RecurrenceUntilObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $GetParam{RecurrenceUntil},
                    },
                );
                if ( $RecurrenceUntilObject < $StartTimeObject ) {
                    $GetParam{RecurrenceUntil} = $GetParam{StartTime};
                }

                $GetParam{RecurrenceCount} = undef;
            }

            # for ... time(s)
            elsif ( $GetParam{RecurrenceLimit} eq '2' ) {
                $GetParam{RecurrenceUntil} = undef;
            }
        }

        # Determine notification custom type, if supplied.
        if ( defined $GetParam{NotificationTemplate} ) {
            if ( $GetParam{NotificationTemplate} ne 'Custom' ) {
                $GetParam{NotificationCustom} = '';
            }
            elsif ( $GetParam{NotificationCustomRelativeInput} ) {
                $GetParam{NotificationCustom} = 'relative';
            }
            elsif ( $GetParam{NotificationCustomDateTimeInput} ) {
                $GetParam{NotificationCustom} = 'datetime';

                $GetParam{NotificationCustomDateTime} = sprintf(
                    "%04d-%02d-%02d %02d:%02d:00",
                    $GetParam{NotificationCustomDateTimeYear},
                    $GetParam{NotificationCustomDateTimeMonth},
                    $GetParam{NotificationCustomDateTimeDay},
                    $GetParam{NotificationCustomDateTimeHour},
                    $GetParam{NotificationCustomDateTimeMinute}
                );

                my $NotificationCustomDateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String   => $GetParam{NotificationCustomDateTime},
                        TimeZone => $Self->{UserTimeZone},
                    },
                );

                if ( $Self->{UserTimeZone} ) {
                    $NotificationCustomDateTimeObject->ToOTOBOTimeZone();
                }

                $GetParam{NotificationCustomDateTime} = $NotificationCustomDateTimeObject->ToString();
            }
        }

# RotherOSS / AppointmentToTicket
        my %FutureTask;
        if ( %Appointment ) {
            my $TaskID;
            if ( $Appointment{FutureTaskID} ) {
                $TaskID = $Appointment{FutureTaskID};
            }
            # Only for parent appointments
            elsif ( $Appointment{Recurring} ) {
                # Check all appointments of series for future task id
                my @AppointmentList = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentList(
                    CalendarID => $Appointment{CalendarID},
                    ParentID => $Appointment{ParentID} || $Appointment{AppointmentID},
                );
                my %ParentAppointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet( AppointmentID => $Appointment{ParentID} || $Appointment{AppointmentID} );
                push @AppointmentList, \%ParentAppointment;

                APPOINTMENTLIST:
                for my $RecurringAppointment (@AppointmentList) {
                    if ( $RecurringAppointment->{FutureTaskID} ) {
                        $TaskID = $RecurringAppointment->{FutureTaskID};
                        last APPOINTMENTLIST;
                    }
                }
            }
            if ( $TaskID ) {
                %FutureTask = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB')->FutureTaskGet(
                    TaskID => $TaskID,
                );
            }
        }

        my @DynamicFieldConfigs;
        if ( $GetParam{TicketTemplate} && defined $Config->{DynamicField} ) {
            my $DynamicFieldConfigsRef= $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
                Valid       => 1,
                ObjectType  => [ 'Ticket', 'Article' ],
                FieldFilter => $Config->{DynamicField} || {},
            );
            @DynamicFieldConfigs = defined $DynamicFieldConfigsRef ? @{ $DynamicFieldConfigsRef } : ();
        }

        my %UserPreferences = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
            UserID => $Self->{UserID},
        );

        my %DynamicFieldValues;
        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @DynamicFieldConfigs ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                DynamicFieldConfig => $DynamicFieldConfig,
            );

            # Validate dynamic field value
            my $ValidationResult = $DynamicFieldBackendObject->EditFieldValueValidate(
                DynamicFieldConfig => $DynamicFieldConfig,
                PossibleValuesFilter => IsHashRefWithData($PossibleValues) ? $PossibleValues : undef,
                ParamObject => $ParamObject,
                Mandatory => $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
            );

            if ( !IsHashRefWithData($ValidationResult) ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( 'Could not perform validation on field %s!', $DynamicFieldConfig->{Label} ),
                    Comment => Translatable('Please contact the administrator.'),
                );
            }
            elsif ( $ValidationResult->{ServerError} ) {
                return $LayoutObject->ErrorScreen(
                    Message => $LayoutObject->{LanguageObject}->Translate( $ValidationResult->{ErrorMessage} ),
                    Comment => Translatable('Please contact the administrator.'),
                );
            }

            # extract the dynamic field value from the web request
            $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ParamObject        => $ParamObject,
                LayoutObject       => $LayoutObject,
            );

            if ( !$DynamicFieldValues{ $DynamicFieldConfig->{Name} }
                || (ref($DynamicFieldValues{ $DynamicFieldConfig->{Name} }) eq 'ARRAY'
                    && !IsArrayRefWithData($DynamicFieldValues{ $DynamicFieldConfig->{Name} }))
            ) {
                # extract the dynamic field value from the web request with approach for array
                $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
                    DynamicFieldConfig => { $DynamicFieldConfig->%*, Name => $DynamicFieldConfig->{Name} . '[]' },
                    ParamObject        => $ParamObject,
                    LayoutObject       => $LayoutObject,
                );
            }
        }

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @DynamicFieldConfigs ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfig->{Config} );
            next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

            # to store dynamic field value from database (or undefined)
            my $Value;

            # Check if the user has a user specific default value for
            # the dynamic field, otherwise will use Dynamic Field default value
            # get default value from dynamic field config (if any)
            $Value = $DynamicFieldConfig->{Config}->{DefaultValue} || '';

            # override the value from user preferences if is set
            if ( $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} } ) {
                $Value = $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} };
            }

            if ( $DynamicFieldValues{$DynamicFieldConfig->{Name}} ) {
                $Value= $DynamicFieldValues{$DynamicFieldConfig->{Name}};
            }

            $GetParam{DynamicFields}->{ $DynamicFieldConfig->{Name} } = $Value;
        }

        # Parse possibly multiple customer users
        if ( @MultipleCustomer ) {
            for my $CustomerUser (@MultipleCustomer) {
                my $CustomerUserIdentifier = $CustomerUser->{CustomerKey} ? $CustomerUser->{CustomerKey} : $CustomerUser->{CustomerElement};
                if ( $CustomerUser->{CustomerSelected} ) {
                    $GetParam{SelectedCustomerUser} = $CustomerUserIdentifier;
                }
                if ( $GetParam{CustomerUser} ) {
                    $GetParam{CustomerUser} .= ",$CustomerUserIdentifier";
                }
                else {
                    $GetParam{CustomerUser} = $CustomerUserIdentifier;
                }
            }
        }

        # fetch customer id for selected customer user
        my %SelectedCustomerUserData = $CustomerUserObject->CustomerUserDataGet(
            User => $GetParam{SelectedCustomerUser},
        );
        $GetParam{CustomerID} = %SelectedCustomerUserData ? $SelectedCustomerUserData{CustomerID} : '';
# EO AppointmentToTicket

        # team
        if ( $GetParam{'TeamID[]'} ) {
            my @TeamIDs = $ParamObject->GetArray( Param => 'TeamID[]' );
            $GetParam{TeamID} = \@TeamIDs;
        }
        else {
            $GetParam{TeamID} = undef;
        }

        # resources
        if ( $GetParam{'ResourceID[]'} ) {
            my @ResourceID = $ParamObject->GetArray( Param => 'ResourceID[]' );
            $GetParam{ResourceID} = \@ResourceID;
        }
        else {
            $GetParam{ResourceID} = undef;
        }

        # Check if dealing with ticket appointment.
        if ( $Appointment{TicketAppointmentRuleID} ) {

            # Make sure readonly values stay unchanged.
            $GetParam{Title}      = $Appointment{Title};
            $GetParam{CalendarID} = $Appointment{CalendarID};
            $GetParam{AllDay}     = undef;
            $GetParam{Recurring}  = undef;

            my $Rule = $CalendarObject->TicketAppointmentRuleGet(
                CalendarID => $Appointment{CalendarID},
                RuleID     => $Appointment{TicketAppointmentRuleID},
            );

            # Recalculate end time based on time preset.
            if ( IsHashRefWithData($Rule) ) {
                if ( $Rule->{EndDate} =~ /^Plus_([0-9]+)$/ && $GetParam{StartTime} ) {
                    my $Preset = int $1;

                    my $EndTimeObject = $Kernel::OM->Create(
                        'Kernel::System::DateTime',
                        ObjectParams => {
                            String => $GetParam{StartTime},    # base on start time
                        },
                    );

                    # Calculate end time using preset value.
                    $EndTimeObject->Add(
                        Minutes => $Preset,
                    );
                    $GetParam{EndTime} = $EndTimeObject->ToString();
                }
            }
        }

        my $Success;

        # reset empty parameters
        for my $Param ( sort keys %GetParam ) {
            if ( !$GetParam{$Param} ) {
                $GetParam{$Param} = undef;
            }
        }

        # pass current user ID
        $GetParam{UserID} = $Self->{UserID};

        # Get passed plugin parameters.
        my @PluginParams = grep { $_ =~ /^Plugin_/ } keys %GetParam;

# RotherOSS / AppointmentToTicket
        if ( !@PluginParams ) {
            # Coming from either drag and drop or resize, filling params with existing data if present
            if ( $GetParam{AppointmentID} ) {
                my %Appointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet(
                    AppointmentID => $GetParam{AppointmentID},
                );

                my $FutureTaskID;
                if ( $Appointment{FutureTaskID} ) {
                    $FutureTaskID = $Appointment{FutureTaskID};
                }
                elsif ( $Appointment{Recurring} || $Appointment{ParentID} ) {
                    my @AppointmentList = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentList(
                        CalendarID => $Appointment{CalendarID},
                        ParentID => $Appointment{ParentID} || $Appointment{AppointmentID},
                    );
                    my %ParentAppointment = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentGet(
                        AppointmentID => $Appointment{ParentID} || $Appointment{AppointmentID},
                    );
                    push @AppointmentList, \%ParentAppointment;
                    APPOINTMENTRECURRING:
                    for my $RecurringAppointment (@AppointmentList) {
                        if ( $RecurringAppointment->{FutureTaskID} ) {
                            $FutureTaskID = $RecurringAppointment->{FutureTaskID};
                            last APPOINTMENTRECURRING;
                        }
                    }
                }

                if ( $FutureTaskID ) {
                    my %FutureTask = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB')->FutureTaskGet(
                        TaskID => $FutureTaskID,
                    );
                    $GetParam{AppointmentTicket} = {
                        $FutureTask{Data}->{AppointmentTicket}->%*,
                    };
                }
            }
        }

        # Determine ticket custom type, if supplied.
        if ( defined $GetParam{TicketTemplate} ) {
            if ( $GetParam{TicketTemplate} ne 'Custom' ) {
                $GetParam{TicketCustom} = '';
            }
            elsif ( $GetParam{TicketCustomRelativeInput} ) {
                $GetParam{TicketCustom} = 'relative';
            }
            elsif ( $GetParam{TicketCustomDateTimeInput} ) {
                $GetParam{TicketCustom} = 'datetime';

                $GetParam{TicketCustomDateTime} = sprintf(
                    "%04d-%02d-%02d %02d:%02d:00",
                    $GetParam{TicketCustomDateTimeYear},
                    $GetParam{TicketCustomDateTimeMonth},
                    $GetParam{TicketCustomDateTimeDay},
                    $GetParam{TicketCustomDateTimeHour},
                    $GetParam{TicketCustomDateTimeMinute}
                );

                my $TicketCustomDateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String   => $GetParam{TicketCustomDateTime},
                        TimeZone => $Self->{UserTimeZone},
                    },
                );

                if ( $Self->{UserTimeZone} ) {
                    $TicketCustomDateTimeObject->ToOTOBOTimeZone();
                }

                $GetParam{TicketCustomDateTime} = $TicketCustomDateTimeObject->ToString();
            }
        }

        # Handle Ticket Creation on Appointment
        if ($GetParam{AppointmentTicket}) {
            $GetParam{AppointmentTicket} = {
                Subject                   => $GetParam{Title},
                Title                     => $GetParam{Title},
                Content                   => $GetParam{Description},
                UserID                    => $Self->{UserID},
                Lock                      => 'unlock',
                OwnerID                   => 1,
                Template                  => $GetParam{TicketTemplate},
                Time                      => $GetParam{TicketTime},
                Custom                    => $GetParam{TicketCustom},
                CustomRelativeUnit        => $GetParam{TicketCustomRelativeUnit},
                CustomRelativeUnitCount   => $GetParam{TicketCustomRelativeUnitCount},
                CustomRelativePointOfTime => $GetParam{TicketCustomRelativePointOfTime},
                CustomDateTime            => $GetParam{TicketCustomDateTime},
                QueueID                   => $GetParam{Dest},
                CustomerID                => $GetParam{CustomerID},
                CustomerUser              => $GetParam{CustomerUser},
                SelectedCustomerUser      => $GetParam{SelectedCustomerUser},
                PriorityID                => $GetParam{PriorityID},
                StateID                   => $GetParam{NextStateID},
                ServiceID                 => $GetParam{ServiceID},
                SLAID                     => $GetParam{SLAID},
                TypeID                    => $GetParam{TypeID},
                ArticleVisibleForCustomer => $GetParam{TicketArticleVisibleForCustomer},
                DynamicFields             => $GetParam{DynamicFields},
                $GetParam{AppointmentTicket}->%*,
            };
        }
        else {
            $GetParam{AppointmentTicket} = {
                Subject                   => $GetParam{Title},
                Title                     => $GetParam{Title},
                Content                   => $GetParam{Description},
                UserID                    => $Self->{UserID},
                Lock                      => 'unlock',
                OwnerID                   => 1,
                Template                  => $GetParam{TicketTemplate},
                Time                      => $GetParam{TicketTime},
                Custom                    => $GetParam{TicketCustom},
                CustomRelativeUnit        => $GetParam{TicketCustomRelativeUnit},
                CustomRelativeUnitCount   => $GetParam{TicketCustomRelativeUnitCount},
                CustomRelativePointOfTime => $GetParam{TicketCustomRelativePointOfTime},
                CustomDateTime            => $GetParam{TicketCustomDateTime},
                QueueID                   => $GetParam{Dest},
                CustomerID                => $GetParam{CustomerID},
                CustomerUser              => $GetParam{CustomerUser},
                SelectedCustomerUser      => $GetParam{SelectedCustomerUser},
                PriorityID                => $GetParam{PriorityID},
                StateID                   => $GetParam{NextStateID},
                ServiceID                 => $GetParam{ServiceID},
                SLAID                     => $GetParam{SLAID},
                TypeID                    => $GetParam{TypeID},
                ArticleVisibleForCustomer => $GetParam{TicketArticleVisibleForCustomer},
                DynamicFields             => $GetParam{DynamicFields},
            };
        }
# EO AppointmentToTicket

        if (%Appointment) {

            # Continue only if coming from edit screen
            #   (there is at least one passed plugin parameter).
            if (@PluginParams) {

                # Get all related appointments before the update.
                my @RelatedAppointments  = ( $Appointment{AppointmentID} );
                my @CalendarAppointments = $AppointmentObject->AppointmentList(
                    CalendarID => $Appointment{CalendarID},
                );

                # If we are dealing with a parent, include any child appointments.
                push @RelatedAppointments,
                    map {
                        $_->{AppointmentID}
                    }
                    grep {
                        defined $_->{ParentID}
                        && $_->{ParentID} eq $Appointment{AppointmentID}
                    } @CalendarAppointments;

                # Remove all existing links.
                for my $CurrentAppointmentID (@RelatedAppointments) {
                    my $Success = $PluginObject->PluginLinkDelete(
                        AppointmentID => $CurrentAppointmentID,
                        UserID        => $Self->{UserID},
                    );

                    if ( !$Success ) {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "Links could not be deleted for appointment $CurrentAppointmentID!",
                        );
                    }
                }
            }

            $Success = $AppointmentObject->AppointmentUpdate(
                %Appointment,
                %GetParam,
            );
        }
        else {
            $Success = $AppointmentObject->AppointmentCreate(
                %GetParam,
            );
        }

        my $AppointmentID = $GetParam{AppointmentID} ? $GetParam{AppointmentID} : $Success;

        if ($AppointmentID) {

            # Continue only if coming from edit screen
            #   (there is at least one passed plugin parameter).
            if (@PluginParams) {

                # Get fresh appointment data.
                %Appointment = $AppointmentObject->AppointmentGet(
                    AppointmentID => $AppointmentID,
                );

                # Process all related appointments.
                my @RelatedAppointments  = ($AppointmentID);
                my @CalendarAppointments = $AppointmentObject->AppointmentList(
                    CalendarID => $Appointment{CalendarID},
                );

                # If we are dealing with a parent, include any child appointments as well.
                push @RelatedAppointments,
                    map {
                        $_->{AppointmentID}
                    }
                    grep {
                        defined $_->{ParentID}
                        && $_->{ParentID} eq $AppointmentID
                    } @CalendarAppointments;

                # Process passed plugin parameters.
                for my $PluginParam (@PluginParams) {
                    my $PluginData = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
                        Data => $GetParam{$PluginParam},
                    );
                    my $PluginKey = $PluginParam;
                    $PluginKey =~ s/^Plugin_//;

                    # Execute link add method of the plugin.
                    if ( IsArrayRefWithData($PluginData) ) {
                        for my $LinkID ( @{$PluginData} ) {
                            for my $CurrentAppointmentID (@RelatedAppointments) {
                                my $Link = $PluginObject->PluginLinkAdd(
                                    AppointmentID => $CurrentAppointmentID,
                                    PluginKey     => $PluginKey,
                                    PluginData    => $LinkID,
                                    UserID        => $Self->{UserID},
                                );

                                if ( !$Link ) {
                                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                                        Priority => 'error',
                                        Message  => "Link could not be created for appointment $CurrentAppointmentID!",
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }

        # build JSON output
        $JSON = $LayoutObject->JSONEncode(
            Data => {
                Success       => $Success ? 1 : 0,
                AppointmentID => $AppointmentID,
            },
        );
    }

# RotherOSS / AppointmentToTicket
    # ------------------------------------------------------------ #
    # AJAX update
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AJAXUpdate' ) {

        my $Dest        = $ParamObject->GetParam( Param => 'Dest' ) || '';
        # TODO Check how this is used later on since in case of external customer user, selected is not in SelectedCustomer but in CustomerSelected
        my $CustomerUser   = $ParamObject->GetParam( Param => 'SelectedCustomerUser' );
        my $ElementChanged = $ParamObject->GetParam( Param => 'ElementChanged' ) || '';
        my $QueueID        = '';

        $QueueID = $Dest;
        $GetParam{QueueID} = $QueueID;

        # get list type
        my $TreeView = 0;
        if ( $ConfigObject->Get('Ticket::Frontend::ListType') eq 'tree' ) {
            $TreeView = 1;
        }

        my $Autoselect = $ConfigObject->Get('TicketACL::Autoselect') || undef;
        my $ACLPreselection;
        if ( $ConfigObject->Get('TicketACL::ACLPreselection') ) {

            # get cached preselection rules
            my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
            $ACLPreselection = $CacheObject->Get(
                Type => 'TicketACL',
                Key  => 'Preselection',
            );
            if ( !$ACLPreselection ) {
                $ACLPreselection = $FieldRestrictionsObject->SetACLPreselectionCache();
            }
        }

        my %Convergence = (
            StdFields => 0,
            Fields    => 0,
        );
        my %ChangedElements        = $ElementChanged                                        ? ( $ElementChanged => 1 ) : ();
        my %ChangedElementsDFStart = $ElementChanged                                        ? ( $ElementChanged => 1 ) : ();
        my %ChangedStdFields       = $ElementChanged && $ElementChanged !~ /^DynamicField_/ ? ( $ElementChanged => 1 ) : ();

        my $LoopProtection = 100;
        my %StdFieldValues;
        my %DynFieldStates = (
            Visibility => {},
            Fields     => {},
        );

        until ( $Convergence{Fields} ) {

            # determine standard field input
            until ( $Convergence{StdFields} ) {

                my %NewChangedElements;

                # which standard fields to check - FieldID => GetParamValue (neccessary for Dest)
                my %Check = (
                    Dest        => 'QueueID',
                    NextStateID => 'NextStateID',
                    PriorityID  => 'PriorityID',
                    ServiceID   => 'ServiceID',
                    SLAID       => 'SLAID',
                    TypeID      => 'TypeID',
                );
                if ($ACLPreselection) {
                    FIELD:
                    for my $FieldID ( sort keys %Check ) {
                        if ( !$ACLPreselection->{Fields}{$FieldID} ) {
                            $Kernel::OM->Get('Kernel::System::Log')->Log(
                                Priority => 'debug',
                                Message  => "$FieldID not defined in TicketACL preselection rules!"
                            );
                            next FIELD;
                        }
                        if ( $Autoselect && $Autoselect->{$FieldID} && $ChangedElements{$FieldID} ) {
                            next FIELD;
                        }
                        for my $Element ( sort keys %ChangedElements ) {
                            if (
                                $ACLPreselection->{Rules}{Ticket}{$Element}{$FieldID}
                                || $Self->{InternalDependancy}{$Element}{$FieldID}
                                )
                            {
                                next FIELD;
                            }
                            if ( !$ACLPreselection->{Fields}{$Element} ) {
                                $Kernel::OM->Get('Kernel::System::Log')->Log(
                                    Priority => 'debug',
                                    Message  => "$Element not defined in TicketACL preselection rules!"
                                );
                                next FIELD;
                            }
                        }

                        # delete unaffected fields
                        delete $Check{$FieldID};
                    }
                }

                # for each standard field which has to be checked, run the defined method
                METHOD:
                for my $Field ( @{ $Self->{FieldMethods} } ) {
                    next METHOD if !$Check{ $Field->{FieldID} };

                    # use $Check{ $Field->{FieldID} } for Dest=>QueueID
                    $StdFieldValues{ $Check{ $Field->{FieldID} } } = $Field->{Method}->(
                        $Self,
                        %GetParam,
                        CustomerUserID => $CustomerUser || '',
                        QueueID        => $GetParam{TicketQueueID},
                        Services       => $StdFieldValues{TicketServiceID} || undef,    # needed for SLAID
                    );

                    # special stuff for QueueID/Dest: Dest is "QueueID||QueueName" => "QueueName";
                    if ( $Field->{FieldID} eq 'Dest' ) {
                        TOs:
                        for my $QueueID ( sort keys %{ $StdFieldValues{QueueID} } ) {
                            next TOs if ( $StdFieldValues{QueueID}{$QueueID} eq '-' );
                            $StdFieldValues{Dest}{$QueueID} = $StdFieldValues{QueueID}{$QueueID};
                        }

                        # check current selection of QueueID (Dest will be done together with the other fields)
                        if ( $GetParam{QueueID} && !$StdFieldValues{Dest}{ $GetParam{Dest} } ) {
                            $GetParam{QueueID} = '';
                        }

                        # autoselect
                        elsif ( !$GetParam{QueueID} && $Autoselect && $Autoselect->{Dest} ) {
                            $GetParam{QueueID} = $FieldRestrictionsObject->Autoselect(
                                PossibleValues => $StdFieldValues{QueueID},
                            ) || '';
                        }
                    }

                    # check whether current selected value is still valid for the field
                    if (
                        $GetParam{ $Field->{FieldID} }
                        && !$StdFieldValues{ $Field->{FieldID} }{ $GetParam{ $Field->{FieldID} } }
                        )
                    {
                        # if not empty the field
                        $GetParam{ $Field->{FieldID} }           = '';
                        $NewChangedElements{ $Field->{FieldID} } = 1;
                        $ChangedStdFields{ $Field->{FieldID} }   = 1;
                    }

                    # autoselect
                    elsif ( !$GetParam{ $Field->{FieldID} } && $Autoselect && $Autoselect->{ $Field->{FieldID} } ) {
                        $GetParam{ $Field->{FieldID} } = $FieldRestrictionsObject->Autoselect(
                            PossibleValues => $StdFieldValues{ $Field->{FieldID} },
                        ) || '';
                        if ( $GetParam{ $Field->{FieldID} } ) {
                            $NewChangedElements{ $Field->{FieldID} } = 1;
                            $ChangedStdFields{ $Field->{FieldID} }   = 1;
                        }
                    }
                }

                if ( !%NewChangedElements ) {
                    $Convergence{StdFields} = 1;
                }
                else {
                    %ChangedElements = %NewChangedElements;
                }

                %ChangedElementsDFStart = (
                    %ChangedElementsDFStart,
                    %NewChangedElements,
                );

                if ( $LoopProtection-- < 1 ) {
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "Ran into unresolvable loop!",
                    );
                    return;
                }

            }

            %ChangedElements        = %ChangedElementsDFStart;
            %ChangedElementsDFStart = ();

            # check dynamic fields
            my %CurFieldStates;
            if (%ChangedElements) {

                # get values and visibility of dynamic fields
                %CurFieldStates = $FieldRestrictionsObject->GetFieldStates(
                    TicketObject              => $TicketObject,
                    DynamicFields             => $Self->{DynamicField},
                    DynamicFieldBackendObject => $DynamicFieldBackendObject,
                    ChangedElements           => \%ChangedElements,            # optional to reduce ACL evaluation
                    Action                    => $Self->{Action},
                    UserID                    => $Self->{UserID},
                    TicketID                  => $Self->{TicketID},
                    FormID                    => $Self->{FormID},
                    CustomerUser              => $CustomerUser || '',
                    GetParam                  => {
                        %GetParam,
                        OwnerID => $GetParam{NewUserID},
                    },
                    Autoselect      => $Autoselect,
                    ACLPreselection => $ACLPreselection,
                    LoopProtection  => \$LoopProtection,
                );

                # combine FieldStates
                $DynFieldStates{Fields} = {
                    %{ $DynFieldStates{Fields} },
                    %{ $CurFieldStates{Fields} },
                };
                $DynFieldStates{Visibility} = {
                    %{ $DynFieldStates{Visibility} },
                    %{ $CurFieldStates{Visibility} },
                };

                # store new values
                $GetParam{DynamicField} = {
                    %{ $GetParam{DynamicField} },
                    %{ $CurFieldStates{NewValues} },
                };
            }
            # if dynamic fields changed, check standard fields again
            if ( %CurFieldStates && IsHashRefWithData( $CurFieldStates{NewValues} ) ) {
                $Convergence{StdFields} = 0;
                %ChangedElements = map { $_ => 1 } keys %{ $CurFieldStates{NewValues} };
            }
            else {
                $Convergence{Fields} = 1;
            }

        }

        # update Dynamic Fields Possible Values via AJAX
        my @DynamicFieldAJAX;

        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $Index ( sort keys %{ $DynFieldStates{Fields} } ) {
            my $DynamicFieldConfig = $Self->{DynamicField}->{$Index};

            my $DataValues = $DynFieldStates{Fields}{$Index}{NotACLReducible}
                ? $GetParam{DynamicField}{"DynamicField_$DynamicFieldConfig->{Name}"}
                :
                (
                    $DynamicFieldBackendObject->BuildSelectionDataGet(
                        DynamicFieldConfig => $DynamicFieldConfig,
                        PossibleValues     => $DynFieldStates{Fields}{$Index}{PossibleValues},
                        Value              => $GetParam{DynamicField}{"DynamicField_$DynamicFieldConfig->{Name}"},
                    )
                    || $DynFieldStates{Fields}{$Index}{PossibleValues}
                );

            # add dynamic field to the list of fields to update
            push @DynamicFieldAJAX, {
                Name        => 'DynamicField_' . $DynamicFieldConfig->{Name},
                Data        => $DataValues,
                SelectedID  => $GetParam{DynamicField}{"DynamicField_$DynamicFieldConfig->{Name}"},
                Translation => $DynamicFieldConfig->{Config}->{TranslatableValues} || 0,
                Max         => 100,
            };
        }

        # define dynamic field visibility
        if ( IsHashRefWithData( $DynFieldStates{Visibility} ) ) {
            push @DynamicFieldAJAX, {
                Name => 'Restrictions_Visibility',
                Data => $DynFieldStates{Visibility},
            };
        }

        # build AJAX return for the standard fields
        my @StdFieldAJAX;
        my %Attributes = (
            Dest => {
                Translation  => 0,
                PossibleNone => 1,
                TreeView     => $TreeView,
                Max          => 100,
            },
            NextStateID => {
                Translation => 1,
                Max         => 100,
            },
            PriorityID => {
                Translation => 1,
                Max         => 100,
            },
            ServiceID => {
                PossibleNone => 1,
                Translation  => 0,
                TreeView     => $TreeView,
                Max          => 100,
            },
            SLAID => {
                PossibleNone => 1,
                Translation  => 0,
                Max          => 100,
            },
            TypeID => {
                PossibleNone => 1,
                Translation  => 0,
                Max          => 100,
            }
        );
        delete $StdFieldValues{QueueID};
        for my $Field ( sort keys %StdFieldValues ) {
            push @StdFieldAJAX, {
                Name       => $Field,
                Data       => $StdFieldValues{$Field},
                SelectedID => $GetParam{$Field},
                %{ $Attributes{$Field} },
            };
        }

        my $JSON = $LayoutObject->BuildSelectionJSON(
            [
                @StdFieldAJAX,
                @DynamicFieldAJAX,
            ],
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );

    }
# EO AppointmentToTicket
    # ------------------------------------------------------------ #
    # delete mask
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'DeleteAppointment' ) {

        if ( $GetParam{AppointmentID} ) {
            my %Appointment = $AppointmentObject->AppointmentGet(
                AppointmentID => $GetParam{AppointmentID},
            );

            my $Success = 0;
            my $Error   = '';

            # Prevent deleting ticket appointment.
            if ( $Appointment{TicketAppointmentRuleID} ) {
                $Error = Translatable('Cannot delete ticket appointment!');
            }
            else {

                # Get all related appointments before the deletion.
                my @RelatedAppointments  = ( $Appointment{AppointmentID} );
                my @CalendarAppointments = $AppointmentObject->AppointmentList(
                    CalendarID => $Appointment{CalendarID},
                );

                # If we are dealing with a parent, include any child appointments.
                push @RelatedAppointments,
                    map {
                        $_->{AppointmentID}
                    }
                    grep {
                        defined $_->{ParentID}
                        && $_->{ParentID} eq $Appointment{AppointmentID}
                    } @CalendarAppointments;

                # Remove all existing links.
                for my $CurrentAppointmentID (@RelatedAppointments) {
                    my $Success = $PluginObject->PluginLinkDelete(
                        AppointmentID => $CurrentAppointmentID,
                        UserID        => $Self->{UserID},
                    );

                    if ( !$Success ) {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "Links could not be deleted for appointment $CurrentAppointmentID!",
                        );
                    }
                }

                $Success = $AppointmentObject->AppointmentDelete(
                    %GetParam,
                    UserID => $Self->{UserID},
                );

                if ( !$Success ) {
                    $Error = Translatable('No permissions!');
                }
            }

            # build JSON output
            $JSON = $LayoutObject->JSONEncode(
                Data => {
                    Success       => $Success,
                    Error         => $Error,
                    AppointmentID => $GetParam{AppointmentID},
                },
            );
        }
    }

    # ------------------------------------------------------------ #
    # update preferences
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'UpdatePreferences' ) {

        my $Success = 0;

        if (
            $GetParam{OverviewScreen} && (
                $GetParam{DefaultView} || $GetParam{CalendarSelection}
                || ( $GetParam{ShownResources} && $GetParam{TeamID} )
                || $GetParam{ShownAppointments}
            )
            )
        {
            my $PreferenceKey;
            my $PreferenceKeySuffix = '';

            if ( $GetParam{DefaultView} ) {
                $PreferenceKey = 'DefaultView';
            }
            elsif ( $GetParam{CalendarSelection} ) {
                $PreferenceKey = 'CalendarSelection';
            }
            elsif ( $GetParam{ShownResources} && $GetParam{TeamID} ) {
                $PreferenceKey       = 'ShownResources';
                $PreferenceKeySuffix = "-$GetParam{TeamID}";
            }
            elsif ( $GetParam{ShownAppointments} ) {
                $PreferenceKey = 'ShownAppointments';
            }

            # set user preferences
            $Success = $Kernel::OM->Get('Kernel::System::User')->SetPreferences(
                Key    => 'User' . $GetParam{OverviewScreen} . $PreferenceKey . $PreferenceKeySuffix,
                Value  => $GetParam{$PreferenceKey},
                UserID => $Self->{UserID},
            );
        }

        elsif ( $GetParam{OverviewScreen} && $GetParam{RestoreDefaultSettings} ) {
            my $PreferenceKey;
            my $PreferenceKeySuffix = '';

            if ( $GetParam{RestoreDefaultSettings} eq 'ShownResources' && $GetParam{TeamID} ) {
                $PreferenceKey       = 'ShownResources';
                $PreferenceKeySuffix = "-$GetParam{TeamID}";
            }

            # blank user preferences
            $Success = $Kernel::OM->Get('Kernel::System::User')->SetPreferences(
                Key    => 'User' . $GetParam{OverviewScreen} . $PreferenceKey . $PreferenceKeySuffix,
                Value  => '',
                UserID => $Self->{UserID},
            );
        }

        # build JSON output
        $JSON = $LayoutObject->JSONEncode(
            Data => {
                Success => $Success,
            },
        );
    }

    # ------------------------------------------------------------ #
    # team list selection update
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'TeamUserList' ) {
        my @TeamIDs = $ParamObject->GetArray( Param => 'TeamID[]' );
        my %TeamUserListAll;

        # Check if team object is registered.
        if ( $Kernel::OM->Get('Kernel::System::Main')->Require( 'Kernel::System::Calendar::Team', Silent => 1 ) ) {
            my $TeamObject = $Kernel::OM->Get('Kernel::System::Calendar::Team');
            my $UserObject = $Kernel::OM->Get('Kernel::System::User');

            TEAMID:
            for my $TeamID (@TeamIDs) {
                next TEAMID if !$TeamID;

                # get list of team members
                my %TeamUserList = $TeamObject->TeamUserList(
                    TeamID => $TeamID,
                    UserID => $Self->{UserID},
                );

                # get user data
                for my $UserID ( sort keys %TeamUserList ) {
                    my %User = $UserObject->GetUserData(
                        UserID => $UserID,
                    );
                    $TeamUserList{$UserID} = $User{UserFullname};
                }

                %TeamUserListAll = ( %TeamUserListAll, %TeamUserList );
            }
        }

        # build JSON output
        $JSON = $LayoutObject->JSONEncode(
            Data => {
                TeamUserList => \%TeamUserListAll,
            },
        );

    }

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _DayOffsetGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Time)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # Get original date components.
    my $OriginalTimeObject = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {
            String => $Param{Time},
        },
    );
    my $OriginalTimeSettings = $OriginalTimeObject->Get();

    # Get destination time according to user timezone.
    my $DestinationTimeObject = $OriginalTimeObject->Clone();
    $DestinationTimeObject->ToTimeZone( TimeZone => $Self->{UserTimeZone} );
    my $DestinationTimeSettings = $DestinationTimeObject->Get();

    # Compare days of two times.
    if ( $OriginalTimeSettings->{Day} == $DestinationTimeSettings->{Day} ) {
        return 0;    # same day
    }
    elsif ( $OriginalTimeObject > $DestinationTimeObject ) {
        return -1;
    }

    return 1;
}

# RotherOSS / AppointmentToTicket
sub _GetPriorities {
    my ( $Self, %Param ) = @_;

    # use default Queue if none is provided
    $Param{QueueID} = $Param{QueueID} || 1;

    # get priority
    my %Priorities;
    if ( $Param{QueueID} ) {
        %Priorities = $Kernel::OM->Get('Kernel::System::Ticket')->TicketPriorityList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Priorities;
}

sub _GetTos {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check own selection
    my %NewTos;
    if ( $ConfigObject->Get('Ticket::Frontend::NewQueueOwnSelection') ) {
        %NewTos = %{ $ConfigObject->Get('Ticket::Frontend::NewQueueOwnSelection') };
    }
    else {

        # SelectionType Queue or SystemAddress?
        my %Tos;
        if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') eq 'Queue' ) {
            %Tos = $Kernel::OM->Get('Kernel::System::Ticket')->MoveList(
                %Param,
                Type    => 'create',
                Action  => $Self->{Action},
                QueueID => $Self->{QueueID},
                UserID  => $Self->{UserID},
            );
        }
        else {
            %Tos = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressQueueList();
        }

        # get create permission queues
        my %UserGroups = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Self->{UserID},
            Type   => 'create',
        );
        my $SystemAddressObject = $Kernel::OM->Get('Kernel::System::SystemAddress');
        my $QueueObject         = $Kernel::OM->Get('Kernel::System::Queue');

        # build selection string
        QUEUEID:
        for my $QueueID ( sort keys %Tos ) {

            my %QueueData = $QueueObject->QueueGet( ID => $QueueID );

            # permission check, can we create new tickets in queue
            next QUEUEID if !$UserGroups{ $QueueData{GroupID} };

            my $String = $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionString')
                || '<Realname> <<Email>> - Queue: <Queue>';
            $String =~ s/<Queue>/$QueueData{Name}/g;
            $String =~ s/<QueueComment>/$QueueData{Comment}/g;

            # remove trailing spaces
            if ( !$QueueData{Comment} ) {
                $String =~ s{\s+\z}{};
            }

            if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') ne 'Queue' ) {
                my %SystemAddressData = $SystemAddressObject->SystemAddressGet(
                    ID => $Tos{$QueueID},
                );
                $String =~ s/<Realname>/$SystemAddressData{Realname}/g;
                $String =~ s/<Email>/$SystemAddressData{Name}/g;
            }
            $NewTos{$QueueID} = $String;
        }
    }

    # add empty selection
    $NewTos{''} = '-';

    return \%NewTos;
}

sub _GetTypes {
    my ( $Self, %Param ) = @_;

    # use default Queue if none is provided
    $Param{QueueID} = $Param{QueueID} || 1;

    # get type
    my %Type;
    if ( $Param{QueueID} || $Param{TicketID} ) {
        %Type = $Kernel::OM->Get('Kernel::System::Ticket')->TicketTypeList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Type;
}

sub _GetStates {
    my ( $Self, %Param ) = @_;

    # use default Queue if none is provided
    $Param{QueueID} = $Param{QueueID} || 1;

    my %NextStates;
    if ( $Param{QueueID} || $Param{TicketID} ) {
        %NextStates = $Kernel::OM->Get('Kernel::System::Ticket')->TicketStateList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%NextStates;
}

sub _GetServices {
    my ( $Self, %Param ) = @_;

    # get service
    my %Service;

    # use default Queue if none is provided
    $Param{QueueID} = $Param{QueueID} || 1;

    # setting customer user id
    $Param{CustomerUserID} = $Param{SelectedCustomerUser};

    # get options for default services for unknown customers
    my $DefaultServiceUnknownCustomer = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Service::Default::UnknownCustomer');

    # check if no CustomerUserID is selected
    # if $DefaultServiceUnknownCustomer = 0 leave CustomerUserID empty, it will not get any services
    # if $DefaultServiceUnknownCustomer = 1 set CustomerUserID to get default services
    if ( !$Param{CustomerUserID} && $DefaultServiceUnknownCustomer ) {
        $Param{CustomerUserID} = '<DEFAULT>';
    }

    # get service list
    if ( $Param{CustomerUserID} ) {
        %Service = $Kernel::OM->Get('Kernel::System::Ticket')->TicketServiceList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Service;
}

sub _GetSLAs {
    my ( $Self, %Param ) = @_;

    # use default Queue if none is provided
    $Param{QueueID} = $Param{QueueID} || 1;

    # get services if they were not determined in an AJAX call
    if ( !defined $Param{Services} ) {
        $Param{Services} = $Self->_GetServices(%Param);
    }

    # get sla
    my %SLA;
    if ( $Param{ServiceID} && $Param{Services} && %{ $Param{Services} } ) {
        if ( $Param{Services}->{ $Param{ServiceID} } ) {
            %SLA = $Kernel::OM->Get('Kernel::System::Ticket')->TicketSLAList(
                %Param,
                Action => $Self->{Action},
                UserID => $Self->{UserID},
            );
        }
    }
    return \%SLA;
}
# EO AppointmentToTicket

1;
