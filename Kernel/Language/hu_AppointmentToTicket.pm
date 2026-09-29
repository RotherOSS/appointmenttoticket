# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
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

package Kernel::Language::hu_AppointmentToTicket;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Template: AgentAppointmentEdit
    $Self->{Translation}->{'Ticket Creation'} = 'Jegylétrehozás';
    $Self->{Translation}->{'Article is visible for customer'} = 'A bejegyzés látható az ügyfélnek';

    # Perl Module: Kernel/Modules/AgentAppointmentEdit.pm
    $Self->{Translation}->{'No ticket creation'} = 'Nincs jegylétrehozás';
    $Self->{Translation}->{'Could not perform validation on field dest!'} = 'Nem sikerült végrehajtani az ellenőrzést a cél mezőn!';
    $Self->{Translation}->{'Could not perform validation on field next state!'} = 'Nem sikerült végrehajtani az ellenőrzést a következő állapot mezőn!';
    $Self->{Translation}->{'Could not perform validation on field service!'} = 'Nem sikerült végrehajtani az ellenőrzést a szolgáltatás mezőn!';
    $Self->{Translation}->{'Could not perform validation on field SLA!'} = 'Nem sikerült végrehajtani az ellenőrzést az SLA mezőn!';
    $Self->{Translation}->{'Could not perform validation on field type!'} = 'Nem sikerült végrehajtani az ellenőrzést a típus mezőn!';
    $Self->{Translation}->{'Could not perform validation on field priority!'} = 'Nem sikerült végrehajtani az ellenőrzést a prioritás mezőn!';

    # SysConfig
    $Self->{Translation}->{'Determines the next possible ticket states, after the creation of a new ticket from a calendar appointment in the agent interface.'} =
        'Meghatározza a következő lehetséges jegyállapotokat egy naptáridőpontból származó új jegy létrehozása után az ügyintézői felületen.';
    $Self->{Translation}->{'Dynamic fields shown in the appointment edit screen of the agent interface'} =
        'Az ügyintézői felület időpont szerkesztése képernyőjén megjelenített dinamikus mezők';
    $Self->{Translation}->{'Sets the default next state for new tickets in the AgentAppointmentEdit interface.'} =
        'Beállítja az új jegyek alapértelmezett következő állapotát az időpont szerkesztésénél az ügyintézői felületen.';
    $Self->{Translation}->{'Sets the default priority for new tickets in the AgentAppointmentEdit interface.'} =
        'Beállítja az új jegyek alapértelmezett prioritását az időpont szerkesztésénél az ügyintézői felületen.';


    push @{ $Self->{JavaScriptStrings} // [] }, (
    '+%s more',
    'All occurrences',
    'All-day',
    'Appointment',
    'Apr',
    'April',
    'Are you sure you want to delete this appointment? This operation cannot be undone.',
    'Aug',
    'August',
    'Close this dialog',
    'Day',
    'Dec',
    'December',
    'Duplicated entry',
    'Feb',
    'February',
    'First select a customer user, then select a customer ID to assign to this ticket.',
    'Fr',
    'Fri',
    'Friday',
    'It is going to be deleted from the field, please try again.',
    'Jan',
    'January',
    'Jul',
    'July',
    'Jump',
    'Jun',
    'June',
    'Just this occurrence',
    'Loading...',
    'Mar',
    'March',
    'May',
    'May_long',
    'Mo',
    'Mon',
    'Monday',
    'Month',
    'Name',
    'Next',
    'Nov',
    'November',
    'OK',
    'Oct',
    'October',
    'Please either turn some off first or increase the limit in configuration.',
    'Press Ctrl+C (Cmd+C) to copy to clipboard',
    'Previous',
    'Resources',
    'Restore default settings',
    'Sa',
    'Sat',
    'Saturday',
    'Save',
    'Select a customer ID to assign to this ticket.',
    'Sep',
    'September',
    'Settings',
    'Su',
    'Sun',
    'Sunday',
    'Th',
    'This address already exists on the address list.',
    'This is a repeating appointment',
    'Thu',
    'Thursday',
    'Timeline Day',
    'Timeline Month',
    'Timeline Week',
    'Today',
    'Too many active calendars',
    'Tu',
    'Tue',
    'Tuesday',
    'We',
    'Wed',
    'Wednesday',
    'Week',
    'Would you like to edit just this occurrence or all occurrences?',
    'more',
    'none',
    );

}

1;
