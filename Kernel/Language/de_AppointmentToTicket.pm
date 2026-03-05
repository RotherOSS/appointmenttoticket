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

package Kernel::Language::de_AppointmentToTicket;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Template: AgentAppointmentEdit
    $Self->{Translation}->{'Ticket Creation'} = 'Ticket-Erstellung';
    $Self->{Translation}->{'Article is visible for customer'} = 'Artikel ist für Kunden sichtbar';

    # Perl Module: Kernel/Modules/AgentAppointmentEdit.pm
    $Self->{Translation}->{'No ticket creation'} = 'Keine Ticket-Erstellung';
    $Self->{Translation}->{'Could not perform validation on field dest!'} = 'Die Überprüfung des Feldes dest konnte nicht durchgeführt werden!';
    $Self->{Translation}->{'Could not perform validation on field next state!'} = 'Die Überprüfung des Feldes next state konnte nicht durchgeführt werden!';
    $Self->{Translation}->{'Could not perform validation on field service!'} = 'Validierung im Außendienst konnte nicht durchgeführt werden!';
    $Self->{Translation}->{'Could not perform validation on field SLA!'} = 'Die Validierung des Feldes SLA konnte nicht durchgeführt werden!';
    $Self->{Translation}->{'Could not perform validation on field type!'} = 'Die Überprüfung des Feldtyps konnte nicht durchgeführt werden!';
    $Self->{Translation}->{'Could not perform validation on field priority!'} = 'Die Überprüfung des Feldes Priorität konnte nicht durchgeführt werden!';

    # SysConfig
    $Self->{Translation}->{'Determines the next possible ticket states, after the creation of a new ticket from a calendar appointment in the agent interface.'} =
        'Ermittelt die nächstmöglichen Ticketstatus, nachdem ein neues Ticket aus einem Kalendertermin in der Agentenoberfläche erstellt wurde.';
    $Self->{Translation}->{'Dynamic fields shown in the appointment edit screen of the agent interface.'} =
        'Dynamische Felder, die in der Terminbearbeitungsmaske der Agentenschnittstelle angezeigt werden';
    $Self->{Translation}->{'Loadermodule registration for the agent interface.'} = 'Loadermodul-Registrierung für die Agentenschnittstelle.';
    $Self->{Translation}->{'Sets the default next state for new tickets in the AgentAppointmentEdit interface.'} =
        'Legt den Standardnachfolgestatus für neue Tickets in der Schnittstelle AgentAppointmentEdit fest.';
    $Self->{Translation}->{'Sets the default priority for new tickets in the AgentAppointmentEdit interface.'} =
        'Legt die Standardpriorität für neue Tickets in der Schnittstelle AgentAppointmentEdit fest.';


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
