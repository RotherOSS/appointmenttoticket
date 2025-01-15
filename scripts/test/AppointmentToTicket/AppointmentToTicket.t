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

use strict;
use warnings;
use utf8;

# Set up the test driver $Self when we are running as a standalone script.
use Kernel::System::UnitTest::RegisterDriver;

our $Self;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

# Do not check emails.
$ConfigObject->Set(
    Key   => 'CheckEmailAddresses',
    Value => 0,
);

# Get necessary objects.
my $CalendarObject    = $Kernel::OM->Get('Kernel::System::Calendar');
my $AppointmentObject = $Kernel::OM->Get('Kernel::System::Calendar::Appointment');
my $ArticleObject     = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $LinkObject        = $Kernel::OM->Get('Kernel::System::LinkObject');
my $SchedulerDBObject = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB');
my $TaskHandlerObject = $Kernel::OM->Get('Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker::AppointmentTicket');
my $TicketObject      = $Kernel::OM->Get('Kernel::System::Ticket');
$Self->Is(
    ref $SchedulerDBObject,
    'Kernel::System::Daemon::SchedulerDB',
    "Kernel::System::Daemon::SchedulerDB->new()",
);

# Create calendar
my $CalendarName = 'Test_' . $HelperObject->GetRandomID();
my %Calendar     = $CalendarObject->CalendarCreate(
    CalendarName => $CalendarName,
    GroupID      => 1,
    Color        => '#FF7700',
    UserID       => 1,
);

my $StartTimeObj = $Kernel::OM->Create(
    'Kernel::System::DateTime'
);
$StartTimeObj->Add(
    Days => 1,
);
my $EndTimeObj = $Kernel::OM->Create(
    'Kernel::System::DateTime'
);
$EndTimeObj->Add(
    Days  => 1,
    Hours => 1,
);

# Create Test Customer User
my $TestCustomerUserLogin = $HelperObject->TestCustomerUserCreate();

# Create Appointment with FutureTask
my $RandomID          = $HelperObject->GetRandomID();
my %AppointmentTicket = (
    Time                      => undef,
    Template                  => 'Start',
    Custom                    => "",
    CustomRelativeUnitCount   => undef,
    CustomRelativeUnit        => 'minutes',
    CustomRelativePointOfTime => 'beforestart',
    CustomDateTime            => undef,
    QueueID                   => 1,
    CustomerID                => $TestCustomerUserLogin,
    CustomerUser              => $TestCustomerUserLogin,
    SelectedCustomerUser      => $TestCustomerUserLogin,
    UserID                    => 1,
    OwnerID                   => 1,
    Lock                      => 'unlock',
    PriorityID                => 3,
    StateID                   => 4,
    ServiceID                 => undef,
    SLAID                     => undef,
    TypeID                    => undef,
    Title                     => 'SomeTitle_' . $RandomID,
    Subject                   => 'SomeTitle_' . $RandomID,
    Content                   => 'SomeDescription_' . $RandomID,
    DynamicFields             => undef,
    ArticleVisibleForCustomer => undef,
);
my $SingleAppointmentID = $AppointmentObject->AppointmentCreate(
    CalendarID                      => $Calendar{CalendarID},
    Title                           => 'SomeTitle_' . $RandomID,
    Description                     => 'SomeDescription_' . $RandomID,
    StartTime                       => $StartTimeObj->ToString(),
    EndTime                         => $EndTimeObj->ToString(),
    UserID                          => 1,
    AppointmentTicket               => \%AppointmentTicket,
    TicketTemplate                  => $AppointmentTicket{Template},
    TicketCustom                    => $AppointmentTicket{Custom},
    TicketCustomRelativeUnit        => $AppointmentTicket{CustomRelativeUnit},
    TicketCustomRelativePointOfTime => $AppointmentTicket{CustomRelativePointOfTime},
);

my %SingleAppointment = $AppointmentObject->AppointmentGet(
    AppointmentID => $SingleAppointmentID,
);

my %FutureTask = $SchedulerDBObject->FutureTaskGet(
    TaskID => $SingleAppointment{FutureTaskID},
);

# Trigger Future Task Execution
$TaskHandlerObject->Run(
    TaskID   => $FutureTask{TaskID},
    TaskName => $FutureTask{Name},
    Data     => $FutureTask{Data},
);

# Check if ticket was created -> via link object
my $LinkList = $LinkObject->LinkList(
    Object => 'Appointment',
    Key    => $SingleAppointmentID,
    State  => 'Valid',
    UserID => 1,
);

$Self->Is(
    scalar keys %{$LinkList},
    1,
    "The number of created links for the appointment is not correct",
);

# Fetch Ticket
my %Ticket = $TicketObject->TicketGet(
    TicketID => ( keys $LinkList->{Ticket}->{Normal}->{Source}->%* )[0],
    UserID   => 1,
);

$Self->IsNot(
    scalar keys %Ticket,
    0,
    "Ticket was not created",
);

# Fetch Article
my @ArticleList = $ArticleObject->ArticleList(
    TicketID => $Ticket{TicketID},
);

$Self->Is(
    scalar @ArticleList,
    1,
    "The number of created articles for the ticket is not correct",
);

my %Article = $ArticleObject->BackendForArticle( %{ $ArticleList[0] } )->ArticleGet( %{ $ArticleList[0] } );
$Self->IsNot(
    scalar keys %Article,
    0,
    "Article was not created",
);

# Create Recurring Appointment with Future Task on Parent Appointment
my $RandomIDRecurring          = $HelperObject->GetRandomID();
my %AppointmentTicketRecurring = (
    Time                      => undef,
    Template                  => 'Start',
    Custom                    => "",
    CustomRelativeUnitCount   => undef,
    CustomRelativeUnit        => 'minutes',
    CustomRelativePointOfTime => 'beforestart',
    CustomDateTime            => undef,
    QueueID                   => 1,
    CustomerID                => $TestCustomerUserLogin,
    CustomerUser              => $TestCustomerUserLogin,
    SelectedCustomerUser      => $TestCustomerUserLogin,
    UserID                    => 1,
    OwnerID                   => 1,
    Lock                      => 'unlock',
    PriorityID                => 3,
    StateID                   => 4,
    ServiceID                 => undef,
    SLAID                     => undef,
    TypeID                    => undef,
    Title                     => 'SomeTitle_' . $RandomIDRecurring,
    Subject                   => 'SomeTitle_' . $RandomIDRecurring,
    Content                   => 'SomeDescription_' . $RandomIDRecurring,
    DynamicFields             => undef,
    ArticleVisibleForCustomer => undef,
);
my $RecurringAppointmentID = $AppointmentObject->AppointmentCreate(
    CalendarID                      => $Calendar{CalendarID},
    Recurring                       => 1,
    RecurrenceDays                  => "",
    RecurrenceMonths                => "",
    RecurrenceMonthDays             => "",
    RecurrenceType                  => "Weekly",
    RecurrenceCustomType            => "CustomDaily",
    RecurrenceInterval              => 1,
    Days                            => 4,
    MonthDays                       => 30,
    Months                          => 6,
    RecurrenceLimit                 => 2,
    RecurrenceUntilDay              => 3,
    RecurrenceUntilMonth            => 7,
    RecurrenceUntilYear             => 2022,
    RecurrenceCount                 => 4,
    Title                           => 'SomeTitle_' . $RandomIDRecurring,
    Description                     => 'SomeDescription_' . $RandomIDRecurring,
    StartTime                       => $StartTimeObj->ToString(),
    EndTime                         => $EndTimeObj->ToString(),
    UserID                          => 1,
    AppointmentTicket               => \%AppointmentTicketRecurring,
    TicketTemplate                  => $AppointmentTicketRecurring{Template},
    TicketCustom                    => $AppointmentTicketRecurring{Custom},
    TicketCustomRelativeUnit        => $AppointmentTicketRecurring{CustomRelativeUnit},
    TicketCustomRelativePointOfTime => $AppointmentTicketRecurring{CustomRelativePointOfTime},
);
$Kernel::OM->Get('Kernel::System::Cache')->CleanUp();

my %RecurringAppointment = $AppointmentObject->AppointmentGet(
    AppointmentID => $RecurringAppointmentID,
);

my %FutureTaskRecurring = $SchedulerDBObject->FutureTaskGet(
    TaskID => $RecurringAppointment{FutureTaskID},
);

my $StartTimePastObj = $Kernel::OM->Create(
    'Kernel::System::DateTime',
);
$StartTimePastObj->Subtract(
    Days => 4,
);

my $EndTimePastObj = $Kernel::OM->Create(
    'Kernel::System::DateTime',
    Days  => 3,
    Hours => 23,
);

# Shift Appointment to the past and check if FutureTask was shifted to the correct Child Appointment
my $Success = $AppointmentObject->AppointmentUpdate(
    %RecurringAppointment,
    AppointmentTicket => $FutureTaskRecurring{Data}->{AppointmentTicket},
    StartTime         => $StartTimePastObj->ToString(),
    EndTime           => $EndTimePastObj->ToString(),
    UserID            => 1,
);

# Check if FutureTask was shifted correctly
my @AppointmentList = $AppointmentObject->AppointmentList(
    CalendarID => $Calendar{CalendarID},
    ParentID   => $RecurringAppointmentID,
);

$Self->Is(
    scalar @AppointmentList,
    3,
    "Number of child appointments is not correct",
);

$Self->IsNot(
    $AppointmentList[0]->{FutureTaskID},
    undef,
    "Future task was not shifted correctly",
);

# Create Appointment with FutureTask, shift it and check FutureTask Execution Time
my $SingleAppointmentID2 = $AppointmentObject->AppointmentCreate(
    CalendarID                      => $Calendar{CalendarID},
    Title                           => 'SomeTitle_' . $RandomID,
    Description                     => 'SomeDescription_' . $RandomID,
    StartTime                       => $StartTimeObj->ToString(),
    EndTime                         => $EndTimeObj->ToString(),
    UserID                          => 1,
    AppointmentTicket               => \%AppointmentTicket,
    TicketTemplate                  => $AppointmentTicket{Template},
    TicketCustom                    => $AppointmentTicket{Custom},
    TicketCustomRelativeUnit        => $AppointmentTicket{CustomRelativeUnit},
    TicketCustomRelativePointOfTime => $AppointmentTicket{CustomRelativePointOfTime},
);

my %SingleAppointment2 = $AppointmentObject->AppointmentGet(
    AppointmentID => $SingleAppointmentID2,
);
my %FutureTask2 = $SchedulerDBObject->FutureTaskGet(
    TaskID => $SingleAppointment2{FutureTaskID},
);
$StartTimeObj->Add(
    Days => 1
);
$EndTimeObj->Add(
    Days => 1,
);

# Update Appointment
$Success = $AppointmentObject->AppointmentUpdate(
    %SingleAppointment2,
    AppointmentTicket => $FutureTask2{Data}->{AppointmentTicket},
    StartTime         => $StartTimeObj->ToString(),
    EndTime           => $EndTimeObj->ToString(),
    UserID            => 1,
);

my %SingleAppointment2Updated = $AppointmentObject->AppointmentGet(
    AppointmentID => $SingleAppointmentID2,
);

$Self->Is(
    $Success,
    1,
    "Appointment update was not successful",
);

my %FutureTask2Updated = $SchedulerDBObject->FutureTaskGet(
    TaskID => $SingleAppointment2Updated{FutureTaskID},
);

$Self->Is(
    $FutureTask2Updated{ExecutionTime},
    $StartTimeObj->ToString(),
    "Future task was not updated correctly",
);

# Create Recurring Appointment with Future Task on Parent Appointment
my $RecurringAppointmentID2 = $AppointmentObject->AppointmentCreate(
    CalendarID                      => $Calendar{CalendarID},
    Title                           => 'SomeTitle_' . $RandomIDRecurring,
    Description                     => 'SomeDescription_' . $RandomIDRecurring,
    StartTime                       => $StartTimeObj->ToString(),
    EndTime                         => $EndTimeObj->ToString(),
    UserID                          => 1,
    AppointmentTicket               => \%AppointmentTicketRecurring,
    TicketTemplate                  => $AppointmentTicketRecurring{Template},
    TicketCustom                    => $AppointmentTicketRecurring{Custom},
    TicketCustomRelativeUnit        => $AppointmentTicketRecurring{CustomRelativeUnit},
    TicketCustomRelativePointOfTime => $AppointmentTicketRecurring{CustomRelativePointOfTime},
);
$Kernel::OM->Get('Kernel::System::Cache')->CleanUp();

my %RecurringAppointment2 = $AppointmentObject->AppointmentGet(
    AppointmentID => $RecurringAppointmentID2,
);

my %FutureTaskRecurring2 = $SchedulerDBObject->FutureTaskGet(
    TaskID => $RecurringAppointment2{FutureTaskID},
);

$StartTimeObj->Add(
    Days => 1
);
$EndTimeObj->Add(
    Days => 1,
);

# Update Appointment
$Success = $AppointmentObject->AppointmentUpdate(
    %RecurringAppointment2,
    AppointmentTicket => $FutureTaskRecurring2{Data}->{AppointmentTicket},
    StartTime         => $StartTimeObj->ToString(),
    EndTime           => $EndTimeObj->ToString(),
    UserID            => 1,
);

$Self->Is(
    $Success,
    1,
    "Appointment update was not successful",
);

my %FutureTaskRecurring2Updated = $SchedulerDBObject->FutureTaskGet(
    TaskID => $RecurringAppointment2{FutureTaskID},
);

$Self->Is(
    $FutureTaskRecurring2Updated{ExecutionTime},
    $StartTimeObj->ToString(),
    "Future task was not updated correctly",
);

$Self->DoneTesting();
