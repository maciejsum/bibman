# This file is part of Bibman -- a console tool for managing BibTeX files.
# Copyright 2017, Maciej Sumalvico <macjan@o2.pl>

# Bibman is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Bibman is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Bibman. If not, see <http://www.gnu.org/licenses/>.

package MainScreen;

use strict;
use warnings;
use feature 'unicode_strings';
use Curses;
use File::Basename;
use Bibman::Bibliography;
use Bibman::EditScreen;
use Bibman::TabularList;
use Bibman::TextInput;
use Bibman::StatusBar;

sub new {
  my $class = shift;
  my $self = {
    list   => new TabularList(4),
    status => new StatusBar(),
    cmd_prompt => new TextInput(""),
    mode   => "normal",               # "normal" or "command"
    filename => undef,
    search_field => undef,
    search_pattern => undef,
    filter_field => undef,
    filter_pattern => undef
  };
  bless $self, $class;
}

sub quit {
  endwin;
  exit 0;
}

sub draw {
  my $self = shift;
  $self->{win}->erase;
  my ($maxy, $maxx);
  $self->{win}->getmaxyx($maxy, $maxx);
  $self->{list}->draw($self->{win}, 0, 0, $maxx, $maxy-3);
  $self->{status}->draw($self->{win}, $maxy-2);
  if ($self->{mode} eq "command") {
    $self->{win}->addstring($maxy-1, 0, ":");
    $self->{cmd_prompt}->draw($self->{win}, 1, $maxy-1, $maxx-2);
  }
}

sub add_entry {
  my $self = shift;
  my $highlight = $self->{list}->{highlight};

  my $entry = $self->{bibliography}->add_entry_at($highlight, "article");
  my $edit = new EditScreen($entry);
  $edit->show($self->{win});
  $self->{list}->add_item_at($highlight, format_entry($entry));
  $self->draw;
  $self->{list}->go_down;
}

sub edit_entry {
  my $self = shift;
  my $idx = $self->{list}->{highlight};
  my $entry = ${$self->{bibliography}->{entries}}[$idx];
  my $edit = new EditScreen($entry);
  $edit->show($self->{win});
  $self->{list}->update_item($idx, format_entry($entry));
  $self->draw;
}

sub delete_entry {
  my $self = shift;
  $self->{bibliography}->delete_entry($self->{list}->{highlight});
  $self->{list}->delete_item($self->{list}->{highlight});
  $self->draw;
}

sub format_entry {
  my $entry = shift;

  my @list_entry = ();
  if ($entry->key) { push @list_entry, $entry->key; } else { push @list_entry, "unknown"; }
  my $authors = Bibliography::format_authors($entry);
  if ($authors) { push @list_entry, $authors; } else { push @list_entry, "unknown"; }
  my $year = $entry->get('year');
  if ($year) { push @list_entry, $year; } else { push @list_entry, ""; }
  my $title = $entry->get('title');
  if ($title) { push @list_entry, $title; } else { push @list_entry, "unknown"; }
  return \@list_entry;
}

sub open_entry {
  my $self = shift;
  # TODO various file extensions: pdf, ps, ...?
  my $entry = ${$self->{bibliography}->{entries}}[$self->{list}->{highlight}];
  my $filename = dirname($self->{filename}) . "/" . $entry->key . ".pdf";
  if (-e $filename) {
    system "rifle $filename";
  }
}

sub get_search_args {
  if ($#_ > 0) {
    return $_[0], $_[1];
  } else {
    return undef, $_[0];
  }
}

sub set_search_args {
  my $self = shift;
  my ($field, $pattern) = get_search_args(@_);
  $self->{search_field} = $field;
  $self->{search_pattern} = $pattern;
  if (!defined($self->{search_pattern})) {
    $self->{search_pattern} = "";
  }
}

sub search {
  my $self = shift;
  $self->set_search_args(@_);
  $self->search_next;
}

sub search_next {
  my $self = shift;
  my $idx = $self->{list}->{highlight};
  do {
    $idx++;
    if ($idx > $#{$self->{list}->{items}}) {
      $idx = 0;
    }
    $idx = $self->{list}->next_visible($idx);
    last if (!defined($idx));
  } while (!($self->match($idx, $self->{search_field}, $self->{search_pattern})
             || $idx == $self->{list}->{highlight}));
  $self->{list}->go_to_item($idx);
}

sub search_prev {
  my $self = shift;
  my $idx = $self->{list}->{highlight};
  do {
    $idx--;
    if ($idx < 0) {
      $idx = $#{$self->{list}->{items}};
    }
    $idx = $self->{list}->prev_visible($idx);
    last if (!defined($idx));
  } while (!($self->match($idx, $self->{search_field}, $self->{search_pattern})
             || $idx == $self->{list}->{highlight}));
  $self->{list}->go_to_item($idx);
}

sub match {
  my $self = shift;
  my $idx = shift;
  my $field = shift;
  my $pattern = shift;
  my $entry = ${$self->{bibliography}->{entries}}[$idx];
  if (defined($field)) {
    my $value = Bibliography::get_property($entry, $field);
    if ((defined($value)) && ($value =~ /$pattern/)) {
      return 1;
    }
  } else {
    for (my $i = 0; $i < $self->{list}->{columns}; $i++) {
      my $list_item = ${$self->{list}->{items}}[$idx];
      if (${$list_item->{values}}[$i] =~ /$pattern/) {
        return 1;
      }
    }
  }
  return 0;
}

sub filter_entries {
  my $self = shift;
  my ($field, $pattern) = get_search_args(@_);
  if (!defined($pattern) || (!$pattern)) {
    for my $item (@{$self->{list}->{items}}) {
      $item->{visible} = 1;
    }
  } else {
    $self->{filter_field} = $field;
    $self->{filter_pattern} = $pattern;
    for (my $i = 0; $i <= $#{$self->{bibliography}->{entries}}; $i++) {
      my $item = ${$self->{list}->{items}}[$i];
      if ($self->match($i, $self->{filter_field}, $self->{filter_pattern})) {
        $item->{visible} = 1;
      } else {
        $item->{visible} = 0;
      }
    }
  }
  my $idx = $self->{list}->next_visible($self->{list}->{highlight});
  if (!defined($idx)) {
    $idx = $self->{list}->prev_visible($self->{list}->{highlight});
  }
  $self->{list}->go_to_item($idx);
  $self->draw;
}

sub move_down {
  my $self = shift;
  my $idx = $self->{list}->{highlight};
  my $entries = $self->{bibliography}->{entries};
  my $list_items = $self->{list}->{items};
  if ($idx < $#$entries) {
    # swap the entry at $idx with the one at $idx+1
    my $entry = $$entries[$idx];
    $$entries[$idx] = $$entries[$idx+1];
    $$entries[$idx+1] = $entry;
    # do the same with the list item
    my $item = $$list_items[$idx];
    $$list_items[$idx] = $$list_items[$idx+1];
    $$list_items[$idx+1] = $item;
    $self->{list}->go_to_item($idx+1);
    $self->draw;
  }
}

sub move_up {
  my $self = shift;
  my $idx = $self->{list}->{highlight};
  my $entries = $self->{bibliography}->{entries};
  my $list_items = $self->{list}->{items};
  if ($idx > 0) {
    # swap the entry at $idx with the one at $idx+1
    my $entry = $$entries[$idx];
    $$entries[$idx] = $$entries[$idx-1];
    $$entries[$idx-1] = $entry;
    # do the same with the list item
    my $item = $$list_items[$idx];
    $$list_items[$idx] = $$list_items[$idx-1];
    $$list_items[$idx-1] = $item;
    $self->{list}->go_to_item($idx-1);
    $self->draw;
  }
}

sub open_bibliography {
  my $self = shift;
  my $filename = shift;

  $self->{filename} = $filename;
  $self->{list}->delete_all_items;

  $self->{bibliography} = new Bibliography();
  $self->{bibliography}->read($filename);

  for my $entry (@{$self->{bibliography}->{entries}}) {
    $self->{list}->add_item(format_entry($entry));
  }

  my $num_entries = $#{$self->{bibliography}->{entries}}+1;
  $self->{status}->set("Loaded $num_entries entries.");
}

sub save_bibliography {
  my $self = shift;
  my $filename = shift;

  if (defined($filename)) {
    $self->{filename} = $filename;
  }
  $self->{bibliography}->write($self->{filename});
  my $num_entries = $#{$self->{bibliography}->{entries}}+1;
  $self->{status}->set("Saved $num_entries entries to $self->{filename}.");
}

sub execute_cmd {
  my $self = shift;
  my $cmdline = shift;

  my @args = split /\s+/, $cmdline;
  my $cmd = shift @args;

  if    ($cmd eq 'add')          { $self->add_entry(@args);                }
  elsif ($cmd eq 'delete')       { $self->delete_entry;                    }
  elsif ($cmd eq 'edit')         { $self->edit_entry;                      }
  elsif ($cmd eq 'filter')       { $self->filter_entries(@args);           }
  elsif ($cmd eq 'go-up')        { $self->{list}->go_up;                   }
  elsif ($cmd eq 'go-to-first')  { $self->{list}->go_to_first;             }
  elsif ($cmd eq 'go-down')      { $self->{list}->go_down;                 }
  elsif ($cmd eq 'go-to-last')   { $self->{list}->go_to_last;              }
  elsif ($cmd eq 'move-down')    { $self->move_down;                       }
  elsif ($cmd eq 'move-up')      { $self->move_up;                         }
  elsif ($cmd eq 'open')         { $self->open_bibliography(@args); $self->draw; }
  elsif ($cmd eq 'open-entry')   { $self->open_entry;                      }
  elsif ($cmd eq 'save')         { $self->save_bibliography(@args);        }
  elsif ($cmd eq 'search')       { $self->search(@args);                   }
  elsif ($cmd eq 'search-next')  { $self->search_next;                     }
  elsif ($cmd eq 'search-prev')  { $self->search_prev;                     }
  elsif ($cmd eq 'quit')         { $self->quit;                            }
  else {
    $self->{status}->set("Unknown command: $cmd", StatusBar::ERROR);
  }
}

sub enter_command_mode {
  my $self = shift;
  my $cmd = shift;
  if (defined($cmd)) {
    $cmd .= " ";
  } else {
    $cmd = "";
  }
  $self->{mode} = "command";
  $self->{cmd_prompt}->{value} = $cmd;
  $self->{cmd_prompt}->{pos} = length $cmd;
  curs_set(1);
  $self->draw;
}

sub exit_command_mode {
  my $self = shift;
  $self->{mode} = "normal";
  curs_set(0);
  $self->draw;
}

sub show {
  my $self = shift;
  my $win = shift;

  $self->{win} = $win;
  $self->draw;

  while (1) {
    my ($c, $key) = $win->getchar();
    my $cmd = '';
    if (defined($key) && ($key == KEY_RESIZE)) {
      $self->draw;
    }  else {
      if ($self->{mode} eq "normal") {
        if (defined($c)) {
          if ($c eq 'k') {
            $self->execute_cmd('go-up');
          } elsif ($c eq 'j') {
            $self->execute_cmd('go-down');
          } elsif ($c eq 'g') {
            $self->execute_cmd('go-to-first');
          } elsif ($c eq 'G') {
            $self->execute_cmd('go-to-last');
          } elsif ($c eq "-") {
            $self->execute_cmd('move-up');
          } elsif ($c eq "+") {
            $self->execute_cmd('move-down');
          } elsif ($c eq 'n') {
            $self->execute_cmd('search-next');
          } elsif ($c eq 'N') {
            $self->execute_cmd('search-prev');
          } elsif ($c eq 'a') {
            $self->execute_cmd('add');
          } elsif ($c eq 's') {
            $self->execute_cmd('save');
          } elsif ($c eq 'S') {
            $self->enter_command_mode("save");
          } elsif ($c eq 'd') {
            $self->execute_cmd('delete');
          } elsif ($c eq 'f') {
            $self->enter_command_mode("filter");
          } elsif ($c eq 'e') {
            $self->execute_cmd('edit');
          } elsif ($c eq 'o') {
            $self->enter_command_mode('open');
          } elsif ($c eq '/') {
            $self->enter_command_mode("search");
          } elsif ($c eq "\n") {
            $self->execute_cmd('open-entry');
          } elsif ($c eq 'q') {
            $self->execute_cmd('quit');
          } elsif ($c eq ':') {
            $self->enter_command_mode;
          }
        } elsif (defined($key)) {
          if ($key == KEY_UP) {
            $self->execute_cmd('go-up');
          } elsif ($key == KEY_DOWN) {
            $self->execute_cmd('go-down');
          } elsif ($key == KEY_HOME) {
            $self->execute_cmd('go-to-first');
          } elsif ($key == KEY_END) {
            $self->execute_cmd('go-to-last');
          } elsif ($key == KEY_ENTER) {
            $self->execute_cmd('open');
          } elsif ($key == KEY_RESIZE) {
            $self->draw;
          }
        }
      } elsif ($self->{mode} eq "command") {
        if (defined($key) && ($key == KEY_BACKSPACE) && (!$self->{cmd_prompt}->{value})) {
          $self->exit_command_mode;
        } elsif (defined($c) && ($c eq "\n")) {
          $self->exit_command_mode;
          $self->execute_cmd($self->{cmd_prompt}->{value});
        } else {
          $self->{cmd_prompt}->key_pressed($c, $key);
        }
      }
    }
  }
}

1;
