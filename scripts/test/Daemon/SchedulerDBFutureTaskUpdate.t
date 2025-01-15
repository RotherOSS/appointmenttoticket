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
my $SchedulerDBObject = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB');
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

# Create appointment
my $RandomID      = $HelperObject->GetRandomID();
my $AppointmentID = $AppointmentObject->AppointmentCreate(
    CalendarID  => $Calendar{CalendarID},
    Title       => 'SomeTitle_' . $RandomID,
    Description => 'SomeDescription_' . $RandomID,
    StartTime   => $StartTimeObj->ToString(),
    EndTime     => $EndTimeObj->ToString(),
    UserID      => 1,
);

# Create test customer user
my $TestCustomerUserLogin = $HelperObject->TestCustomerUserCreate();

# Create initial future task
my $FutureTaskID = $SchedulerDBObject->FutureTaskAdd(
    ExecutionTime => $StartTimeObj->ToString(),
    Type          => 'AppointmentTicket',
    Data          => {
        AppointmentTicket => {
            Time                      => undef,
            Template                  => 'Start',
            Custom                    => undef,
            CustomRelativeUnitCount   => undef,
            CustomRelativeUnit        => 'minutes',
            CustomRelativePointOfTime => 'beforestart',
            CustomDateTime            => undef,
            QueueID                   => 1,
            CustomerID                => $TestCustomerUserLogin,
            CustomerUser              => $TestCustomerUserLogin,
            SelectedCustomerUser      => 'test',
            Title                     => 'SomeTitle_' . $RandomID,
            Subject                   => 'SomeTitle_' . $RandomID,
            Body                      => 'SomeDescription_' . $RandomID,
            UserID                    => 1,
            Lock                      => 'unlock',
            PriorityID                => 3,
            StateID                   => 1,
        },
        AppointmentID => $AppointmentID,
    }
);

# Check if task has been created successfully
$Self->IsNot(
    $FutureTaskID,
    undef,
    "Future task id is undef",
);
$Self->IsNot(
    $FutureTaskID,
    -1,
    "Future task could not be created, Result: $FutureTaskID",
);

my %FutureTask = $SchedulerDBObject->FutureTaskGet(
    TaskID => $FutureTaskID,
);

# Update execution time
my $ExecutionTimeNew = $Kernel::OM->Create(
    'Kernel::System::DateTime'
);
$ExecutionTimeNew->Add(
    Days  => 2,
    Hours => 1,
);
my $Success = $SchedulerDBObject->FutureTaskUpdate(
    TaskID        => $FutureTaskID,
    ExecutionTime => $ExecutionTimeNew->ToString(),
    Data          => {
        AppointmentID     => $FutureTask{Data}->{AppointmentID},
        AppointmentTicket => {
            $FutureTask{Data}->{AppointmentTicket}->%*,
            Title   => 'SomeTitle2_' . $RandomID,
            Subject => 'SomeTitle2_' . $RandomID,
            Body    => 'SomeDescription2_' . $RandomID,
        }
    },
);

$Self->Is(
    $Success,
    1,
    "Future task could not be updated successfully",
);

my %FutureTaskUpdated = $SchedulerDBObject->FutureTaskGet(
    TaskID => $FutureTaskID,
);

$Self->Is(
    $FutureTaskUpdated{ExecutionTime},
    $ExecutionTimeNew->ToString(),
    "Update of future task was successful, but did not change the execution time",
);

$Self->Is(
    $FutureTaskUpdated{Data}->{AppointmentTicket}->{Title},
    'SomeTitle2_' . $RandomID,
    "Update of future task was successful, but did not change the ticket title",
);

# cleanup is done by RestoreDatabase.

$Self->DoneTesting();
