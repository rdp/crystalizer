# this one makes for faster
# @a = 3
# @b = 4
# by doing the lookups locally, in C, instead of having ruby do it for us by a rb_ivar_set call.

module Ruby2CExtension::Plugins

class IVarCache < Ruby2CExtension::Plugin

    include Util

    def initialize(compiler)
        super(compiler)
        @cache_index = Hash.new { |h,k| h[k] = h.size }
        compiler.add_preprocessor(:ivar) { |cfun, node|
            hash = node.last
            vid = hash[:vid]
            key = [vid, cfun.__id__]
            index = @cache_index[key]
            entry = "ivar_cache[#{index}]"
            "cache_ivar_get(&#{entry}, #{cfun.get_self}, #{cfun.sym(vid)})"
        }
        compiler.add_preprocessor(:iasgn) { |cfun, node|
            hash = node.last
            vid = hash[:vid]
            key = [vid, cfun.__id__]
            index = @cache_index[key]
            entry = "ivar_cache[#{index}]"
            "cache_ivar_set(&#{entry}, #{cfun.get_self}, #{cfun.sym(vid)}, #{cfun.comp(hash[:value])})"
        }
    end

    def global_c_code
        code = %{
            typedef struct {
                unsigned num_bins;
                unsigned bin_pos;
            } ivar_cache_entry;
            static ivar_cache_entry ivar_cache[#{@cache_index.size}];
            static void init_ivar_cache() {
                ivar_cache_entry* entry;
                for (entry = &ivar_cache[#{@cache_index.size-1}]; entry >= ivar_cache; --entry) {
                    entry->num_bins = 0;
                    entry->bin_pos = 0;
                }
            }
            typedef struct st_table_entry st_table_entry;
            struct st_table_entry {
                unsigned int hash;
                st_data_t key;
                st_data_t record;
                st_table_entry *next;
            };
            static st_table_entry *st_find_collided(st_table_entry **prev, ID id) {
                st_table_entry *cur = *prev;
                while (cur = cur->next) {
                    if (cur->hash == id) {
                        (*prev)->next = cur->next;
                        cur->next = *prev;
                        *prev = cur;
                        return cur;
                    }
                    prev = &(*prev)->next;
                }
                return 0;
            }
            static VALUE cache_ivar_get(ivar_cache_entry* entry,
                                               VALUE obj, ID id)
            {
                st_table* table = ROBJECT(obj)->iv_tbl;
                unsigned bin_pos;
                st_table_entry *cur;
                switch (TYPE(obj)) {
                    case T_OBJECT:
                    case T_CLASS:
                    case T_MODULE:
                        break;
                    default:
                        return rb_ivar_get(obj, id);
                }
                if (!table) return Qnil;
                if (entry->num_bins==table->num_bins) {
                    bin_pos = entry->bin_pos;
                } else {
                    entry->num_bins = table->num_bins;
                    bin_pos = entry->bin_pos = id % table->num_bins;
                }
                cur = table->bins[bin_pos];
                if (!cur) return Qnil;
                if (cur->hash == id) return cur->record;
                cur = st_find_collided(&table->bins[bin_pos], id);
                return cur ? cur->record : Qnil;
            }
            static VALUE cache_ivar_set(ivar_cache_entry* entry,
                                               VALUE obj, ID id, VALUE val)
            {
                st_table* table;
                unsigned bin_pos;
                st_table_entry *cur;
                if (!OBJ_TAINTED(obj) && rb_safe_level() >= 4 || OBJ_FROZEN(obj))
                    return rb_ivar_set(obj, id, val);
                switch (TYPE(obj)) {
                    case T_OBJECT:
                    case T_CLASS:
                    case T_MODULE:
                        break;
                    default:
                        return rb_ivar_set(obj, id, val);
                }
                table = ROBJECT(obj)->iv_tbl;
                if (!table) {
                    table = ROBJECT(obj)->iv_tbl = st_init_numtable();
                }
                if (entry->num_bins==table->num_bins) {
                    bin_pos = entry->bin_pos;
                } else {
                    entry->num_bins = table->num_bins;
                    bin_pos = entry->bin_pos = id % table->num_bins;
                }
                cur = table->bins[bin_pos];
                if (!cur) {
                    st_add_direct(table, id, val);
                    return val;
                }
                if (cur->hash == id) return (cur->record = val);
                cur = st_find_collided(&table->bins[bin_pos], id);
                if (cur) {
                    return (cur->record = val);
                } else {
                    st_add_direct(table, id, val);
                    return val;
                }
            }
        }
        code
    end

    def init_c_code
        %{
            init_ivar_cache();
        }
    end

end

end

