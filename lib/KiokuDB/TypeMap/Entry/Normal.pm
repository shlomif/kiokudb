#!/usr/bin/perl

package KiokuDB::TypeMap::Entry::Normal;
use Moose;

use namespace::clean -except => 'meta';

with qw(KiokuDB::TypeMap::Entry::Std);

# FIXME collapser and expaner should both be methods in Class::MOP::Class,
# apart from the visit call

sub compile_mappings {
    my ( $self, $class ) = @_;

    my $meta = Class::MOP::get_metaclass_by_name($class);

    if ( $meta->is_immutable ) {
        $self->compile_mappings_immutable($meta);
    } else {
        $self->compile_mappings_mutable($meta);
    }
}

sub compile_collapser {
    my ( $self, $meta ) = @_;

    my ( @names, %readers, %predicates );

    foreach my $attr ( $meta->compute_all_applicable_attributes ) {
        my $name = $attr->name;

        push @names, $name;
        $readers{$name} = $attr->get_read_method_ref->body || sub { $attr->get_value($_[0]) };
        $predicates{$name} = $attr->predicate || sub { $attr->has_value($_[0]) }; # FIXME very very slow
    }

    return sub {
        my ( $self, %args ) = @_;

        my $object = $args{object};

        my %collapsed;

        foreach my $name ( @names ) {
            my $pred = $predicates{$name};
            if ( $object->$pred() ) {
                my $reader = $readers{$name};
                my $value = $object->$reader();
                $collapsed{$name} = ref($value) ? $self->visit($value) : $value;
            }
        }

        return \%collapsed;
    }
}

sub compile_expander {
    my ( $self, $meta ) = @_;

    my %writers;

    foreach my $attr ( $meta->compute_all_applicable_attributes ) {
        my $name = $attr->name;
        $writers{$name} = $attr->get_write_method_ref->body || sub { $attr->set_value($_[0]) };
    }

    return sub {
        my ( $self, $entry ) = @_;

        my $instance = $meta->get_meta_instance->create_instance();

        # note, this is registered *before* any other value expansion, to allow circular refs
        $self->register_object( $entry => $instance );

        my $data = $entry->data;

        foreach my $name ( keys %$data ) {
            my $value = $data->{$name};

            $value = $self->inflate_data($value) if ref $value;

            my $writer = $writers{$name};
            $instance->$writer($value); # FIXME avoid trigger, type constraint etc
        }

        return $instance;
    }
}

sub compile_mappings_immutable {
    my ( $self, $meta ) = @_;
    return (
        $self->compile_collapser($meta),
        $self->compile_expander($meta),
    );
}

sub compile_mappings_mutable {
    my ( $self, $meta ) = @_;

    #warn "Mutable: " . $meta->name;

    return (
        sub {
            my $collapser = $self->compile_collapser($meta);
            shift->$collapser(@_);
        },
        sub {
            my $expander = $self->compile_expander($meta);
            shift->$expander(@_);
        },
    );
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__