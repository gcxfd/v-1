// Copyright (c) 2019-2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

// import v.ast // TODO this results in a compiler bug
import os.cmdline
import os
import v.vcache
import rand

pub enum BuildMode {
	// `v program.v'
	// Build user code only, and add pre-compiled vlib (`cc program.o builtin.o os.o...`)
	default_mode // `v -lib ~/v/os`
	// build any module (generate os.o + os.vh)
	build_module
}

pub enum AssertFailureMode {
	default
	aborts
	backtraces
}

pub enum GarbageCollectionMode {
	no_gc
	boehm_full // full garbage collection mode
	boehm_incr // incremental garbage colletion mode
	boehm_full_opt // full garbage collection mode
	boehm_incr_opt // incremental garbage colletion mode
	boehm_leak // leak detection mode (makes `gc_check_leaks()` work)
}

pub enum OutputMode {
	stdout
	silent
}

pub enum ColorOutput {
	auto
	always
	never
}

pub enum Backend {
	c // The (default) C backend
	js_node // The JavaScript NodeJS backend
	js_browser // The JavaScript browser backend
	js_freestanding // The JavaScript freestanding backend
	native // The Native backend
	interpret // Interpret the ast
}

pub fn (b Backend) is_js() bool {
	return b in [
		.js_node,
		.js_browser,
		.js_freestanding,
	]
}

pub enum CompilerType {
	gcc
	tinyc
	clang
	mingw
	msvc
	cplusplus
}

pub enum Arch {
	_auto
	amd64 // aka x86_64
	arm64 // 64-bit arm
	arm32 // 32-bit arm
	rv64 // 64-bit risc-v
	rv32 // 32-bit risc-v
	i386
	js_node
	js_browser
	js_freestanding
	_max
}

const (
	list_of_flags_with_param = ['o', 'd', 'define', 'b', 'backend', 'cc', 'os', 'target-os', 'cf',
		'cflags', 'path', 'arch']
)

[heap]
pub struct Preferences {
pub mut:
	os          OS // the OS to compile for
	backend     Backend
	build_mode  BuildMode
	arch        Arch
	output_mode OutputMode = .stdout
	// verbosity           VerboseLevel
	is_verbose bool
	// nofmt            bool   // disable vfmt
	is_test           bool     // `v test string_test.v`
	is_script         bool     // single file mode (`v program.v`), main function can be skipped
	is_vsh            bool     // v script (`file.vsh`) file, the `os` module should be made global
	is_livemain       bool     // main program that contains live/hot code
	is_liveshared     bool     // a shared library, that will be used in a -live main program
	is_shared         bool     // an ordinary shared library, -shared, no matter if it is live or not
	is_o              bool     // building an .o file
	is_prof           bool     // benchmark every function
	test_runner       string   // can be 'simple' (fastest, but much less detailed), 'tap', 'normal'
	profile_file      string   // the profile results will be stored inside profile_file
	profile_no_inline bool     // when true, [inline] functions would not be profiled
	profile_fns       []string // when set, profiling will be off by default, but inside these functions (and what they call) it will be on.	
	translated        bool     // `v translate doom.v` are we running V code translated from C? allow globals, ++ expressions, etc
	is_prod           bool     // use "-O2"
	obfuscate         bool     // `v -obf program.v`, renames functions to "f_XXX"
	is_repl           bool
	is_run            bool
	is_debug          bool // turned on by -g or -cg, it tells v to pass -g to the C backend compiler.
	is_vlines         bool // turned on by -g (it slows down .tmp.c generation slightly).
	// NB: passing -cg instead of -g will set is_vlines to false and is_debug to true, thus making v generate cleaner C files,
	// which are sometimes easier to debug / inspect manually than the .tmp.c files by plain -g (when/if v line number generation breaks).
	sanitize               bool   // use Clang's new "-fsanitize" option
	sourcemap              bool   // JS Backend: -sourcemap will create a source map - default false
	sourcemap_inline       bool = true // JS Backend: -sourcemap-inline will embed the source map in the generated JaaScript file -  currently default true only implemented
	sourcemap_src_included bool   // JS Backend: -sourcemap-src-included includes V source code in source map -  default false
	show_cc                bool   // -showcc, print cc command
	show_c_output          bool   // -show-c-output, print all cc output even if the code was compiled correctly
	show_callgraph         bool   // -show-callgraph, print the program callgraph, in a Graphviz DOT format to stdout
	show_depgraph          bool   // -show-depgraph, print the program module dependency graph, in a Graphviz DOT format to stdout
	dump_c_flags           string // `-dump-c-flags file.txt` - let V store all C flags, passed to the backend C compiler in `file.txt`, one C flag/value per line.
	use_cache              bool   // when set, use cached modules to speed up subsequent compilations, at the cost of slower initial ones (while the modules are cached)
	retry_compilation      bool = true // retry the compilation with another C compiler, if tcc fails.
	is_stats               bool   // `v -stats file_test.v` will produce more detailed statistics for the tests that were run
	// TODO Convert this into a []string
	cflags string // Additional options which will be passed to the C compiler.
	// For example, passing -cflags -Os will cause the C compiler to optimize the generated binaries for size.
	// You could pass several -cflags XXX arguments. They will be merged with each other.
	// You can also quote several options at the same time: -cflags '-Os -fno-inline-small-functions'.
	m64                bool         // true = generate 64-bit code, defaults to x64
	ccompiler          string       // the name of the C compiler used
	ccompiler_type     CompilerType // the type of the C compiler used
	third_party_option string
	building_v         bool
	autofree           bool // `v -manualfree` => false, `v -autofree` => true; false by default for now.
	// Disabling `free()` insertion results in better performance in some applications (e.g. compilers)
	compress bool // when set, use `upx` to compress the generated executable
	// generating_vh    bool
	no_builtin       bool // Skip adding the `builtin` module implicitly. The generated C code may not compile.
	enable_globals   bool // allow __global for low level code
	is_fmt           bool
	is_vet           bool
	is_bare          bool   // set by -freestanding
	bare_builtin_dir string // Set by -bare-builtin-dir xyz/ . The xyz/ module should contain implementations of malloc, memset, etc, that are used by the rest of V's `builtin` module. That option is only useful with -freestanding (i.e. when is_bare is true).
	no_preludes      bool   // Prevents V from generating preludes in resulting .c files
	custom_prelude   string // Contents of custom V prelude that will be prepended before code in resulting .c files
	lookup_path      []string
	output_cross_c   bool // true, when the user passed `-os cross`
	output_es5       bool
	prealloc         bool
	vroot            string
	out_name_c       string // full os.real_path to the generated .tmp.c file; set by builder.
	out_name         string
	path             string // Path to file/folder to compile
	// -d vfmt and -d another=0 for `$if vfmt { will execute }` and `$if another ? { will NOT get here }`
	run_only []string // VTEST_ONLY_FN and -run-only accept comma separated glob patterns.
	// Only test_ functions that match these patterns will be run. -run-only is valid only for _test.v files.
	compile_defines     []string    // just ['vfmt']
	compile_defines_all []string    // contains both: ['vfmt','another']
	run_args            []string    // `v run x.v 1 2 3` => `1 2 3`
	printfn_list        []string    // a list of generated function names, whose source should be shown, for debugging
	print_v_files       bool        // when true, just print the list of all parsed .v files then stop.
	skip_running        bool        // when true, do no try to run the produced file (set by b.cc(), when -o x.c or -o x.js)
	skip_warnings       bool        // like C's "-w", forces warnings to be ignored.
	warn_impure_v       bool        // -Wimpure-v, force a warning for JS.fn()/C.fn(), outside of .js.v/.c.v files. TODO: turn to an error by default
	warns_are_errors    bool        // -W, like C's "-Werror", treat *every* warning is an error
	fatal_errors        bool        // unconditionally exit after the first error with exit(1)
	reuse_tmpc          bool        // do not use random names for .tmp.c and .tmp.c.rsp files, and do not remove them
	no_rsp              bool        // when true, pass C backend options directly on the CLI (do not use `.rsp` files for them, some older C compilers do not support them)
	no_std              bool        // when true, do not pass -std=gnu99(linux)/-std=c99 to the C backend
	use_color           ColorOutput // whether the warnings/errors should use ANSI color escapes.
	no_parallel         bool
	is_vweb             bool // skip _ var warning in templates
	only_check_syntax   bool // when true, just parse the files, then stop, before running checker
	check_only          bool // same as only_check_syntax, but also runs the checker
	experimental        bool // enable experimental features
	skip_unused         bool // skip generating C code for functions, that are not used
	show_timings        bool // show how much time each compiler stage took
	is_ios_simulator    bool
	is_apk              bool     // build as Android .apk format
	cleanup_files       []string // list of temporary *.tmp.c and *.tmp.c.rsp files. Cleaned up on successfull builds.
	build_options       []string // list of options, that should be passed down to `build-module`, if needed for -usecache
	cache_manager       vcache.CacheManager
	is_help             bool // -h, -help or --help was passed
	gc_mode             GarbageCollectionMode = .no_gc // .no_gc, .boehm, .boehm_leak, ...
	is_cstrict          bool                  // turn on more C warnings; slightly slower
	assert_failure_mode AssertFailureMode // whether to call abort() or print_backtrace() after an assertion failure
	message_limit       int = 100 // the maximum amount of warnings/errors/notices that will be accumulated
	nofloat             bool              // for low level code, like kernels: replaces f32 with u32 and f64 with u64
	// checker settings:
	checker_match_exhaustive_cutoff_limit int = 12
}

pub fn parse_args(known_external_commands []string, args []string) (&Preferences, string) {
	return parse_args_and_show_errors(known_external_commands, args, false)
}

pub fn parse_args_and_show_errors(known_external_commands []string, args []string, show_output bool) (&Preferences, string) {
	mut res := &Preferences{}
	$if x64 {
		res.m64 = true // follow V model by default
	}
	res.run_only = os.getenv('VTEST_ONLY_FN').split_any(',')
	mut command := ''
	mut command_pos := 0
	// for i, arg in args {
	for i := 0; i < args.len; i++ {
		arg := args[i]
		current_args := args[i..].clone()
		match arg {
			'-apk' {
				res.is_apk = true
				res.build_options << arg
			}
			'-arch' {
				target_arch := cmdline.option(current_args, '-arch', '')
				i++
				target_arch_kind := arch_from_string(target_arch) or {
					eprintln('unknown architecture target `$target_arch`')
					exit(1)
				}
				res.arch = target_arch_kind
				res.build_options << '$arg $target_arch'
			}
			'-assert' {
				assert_mode := cmdline.option(current_args, '-assert', '')
				match assert_mode {
					'aborts' {
						res.assert_failure_mode = .aborts
					}
					'backtraces' {
						res.assert_failure_mode = .backtraces
					}
					else {
						eprintln('unknown assert mode `-gc $assert_mode`, supported modes are:`')
						eprintln('  `-assert aborts`     .... calls abort() after assertion failure')
						eprintln('  `-assert backtraces` .... calls print_backtrace() after assertion failure')
						exit(1)
					}
				}
				i++
			}
			'-show-timings' {
				res.show_timings = true
			}
			'-check-syntax' {
				res.only_check_syntax = true
			}
			'-check' {
				res.check_only = true
			}
			'-h', '-help', '--help' {
				// NB: help is *very important*, just respond to all variations:
				res.is_help = true
			}
			'-v' {
				// `-v` flag is for setting verbosity, but without any args it prints the version, like Clang
				if args.len > 1 {
					res.is_verbose = true
				} else {
					command = 'version'
					command_pos = i
				}
			}
			'-progress' {
				// processed by testing tools in cmd/tools/modules/testing/common.v
			}
			'-Wimpure-v' {
				res.warn_impure_v = true
			}
			'-Wfatal-errors' {
				res.fatal_errors = true
			}
			'-silent' {
				res.output_mode = .silent
			}
			'-cstrict' {
				res.is_cstrict = true
			}
			'-nofloat' {
				res.nofloat = true
				res.compile_defines_all << 'nofloat' // so that `$if nofloat? {` works
			}
			'-gc' {
				gc_mode := cmdline.option(current_args, '-gc', '')
				match gc_mode {
					'', 'none' {
						res.gc_mode = .no_gc
					}
					'boehm_full' {
						res.gc_mode = .boehm_full
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_full')
					}
					'boehm_incr' {
						res.gc_mode = .boehm_incr
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_incr')
					}
					'boehm_full_opt' {
						res.gc_mode = .boehm_full_opt
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_full')
						res.parse_define('gcboehm_opt')
					}
					'boehm_incr_opt' {
						res.gc_mode = .boehm_incr_opt
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_incr')
						res.parse_define('gcboehm_opt')
					}
					'boehm' {
						res.gc_mode = .boehm_full_opt // default mode
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_full')
						res.parse_define('gcboehm_opt')
					}
					'boehm_leak' {
						res.gc_mode = .boehm_leak
						res.parse_define('gcboehm')
						res.parse_define('gcboehm_leak')
					}
					else {
						eprintln('unknown garbage collection mode `-gc $gc_mode`, supported modes are:`')
						eprintln('  `-gc boehm` ............ default GC-mode (currently `boehm_full_opt`)')
						eprintln('  `-gc boehm_full` ....... classic full collection')
						eprintln('  `-gc boehm_incr` ....... incremental collection')
						eprintln('  `-gc boehm_full_opt` ... optimized classic full collection')
						eprintln('  `-gc boehm_incr_opt` ... optimized incremental collection')
						eprintln('  `-gc boehm_leak` ....... leak detection (for debugging)')
						eprintln('  `-gc none` ............. no garbage collection')
						exit(1)
					}
				}
				i++
			}
			'-g' {
				res.is_debug = true
				res.is_vlines = true
				res.build_options << arg
			}
			'-cg' {
				res.is_debug = true
				res.is_vlines = false
				res.build_options << arg
			}
			'-debug-tcc' {
				res.ccompiler = 'tcc'
				res.build_options << '$arg "$res.ccompiler"'
				res.retry_compilation = false
				res.show_cc = true
				res.show_c_output = true
			}
			'-sourcemap' {
				res.sourcemap = true
			}
			'-sourcemap-src-included' {
				res.sourcemap_src_included = true
			}
			'-sourcemap-inline' {
				res.sourcemap_inline = true
			}
			'-repl' {
				res.is_repl = true
			}
			'-live' {
				res.is_livemain = true
			}
			'-sharedlive' {
				res.is_liveshared = true
				res.is_shared = true
			}
			'-shared' {
				res.is_shared = true
			}
			'--enable-globals' {
				eprintln_cond(show_output, '`--enable-globals` flag is deprecated, please use `-enable-globals` instead')
				res.enable_globals = true
			}
			'-enable-globals' {
				res.enable_globals = true
			}
			'-autofree' {
				res.autofree = true
				res.build_options << arg
			}
			'-manualfree' {
				res.autofree = false
				res.build_options << arg
			}
			'-skip-unused' {
				res.skip_unused = true
			}
			'-compress' {
				res.compress = true
			}
			'-freestanding' {
				res.is_bare = true
				res.build_options << arg
			}
			'-no-retry-compilation' {
				res.retry_compilation = false
			}
			'-no-builtin' {
				res.no_builtin = true
				res.build_options << arg
			}
			'-no-preludes' {
				res.no_preludes = true
				res.build_options << arg
			}
			'-prof', '-profile' {
				res.profile_file = cmdline.option(current_args, arg, '-')
				res.is_prof = true
				res.build_options << '$arg $res.profile_file'
				i++
			}
			'-profile-fns' {
				profile_fns := cmdline.option(current_args, arg, '').split(',')
				if profile_fns.len > 0 {
					res.profile_fns << profile_fns
				}
				i++
			}
			'-profile-no-inline' {
				res.profile_no_inline = true
			}
			'-prod' {
				res.is_prod = true
				res.build_options << arg
			}
			'-sanitize' {
				res.sanitize = true
				res.build_options << arg
			}
			'-simulator' {
				res.is_ios_simulator = true
			}
			'-stats' {
				res.is_stats = true
			}
			'-obf', '-obfuscate' {
				res.obfuscate = true
			}
			'-translated' {
				res.translated = true
			}
			'-m32', '-m64' {
				res.m64 = arg[2] == `6`
				res.cflags += ' $arg'
			}
			'-color' {
				res.use_color = .always
			}
			'-nocolor' {
				res.use_color = .never
			}
			'-showcc' {
				res.show_cc = true
			}
			'-show-c-output' {
				res.show_c_output = true
			}
			'-show-callgraph' {
				res.show_callgraph = true
			}
			'-show-depgraph' {
				res.show_depgraph = true
			}
			'-run-only' {
				res.run_only = cmdline.option(current_args, arg, os.getenv('VTEST_ONLY_FN')).split_any(',')
				i++
			}
			'-test-runner' {
				res.test_runner = cmdline.option(current_args, arg, res.test_runner)
				i++
			}
			'-dump-c-flags' {
				res.dump_c_flags = cmdline.option(current_args, arg, '-')
				i++
			}
			'-experimental' {
				res.experimental = true
			}
			'-usecache' {
				res.use_cache = true
			}
			'-nocache' {
				res.use_cache = false
			}
			'-prealloc' {
				res.prealloc = true
				res.build_options << arg
			}
			'-no-parallel' {
				res.no_parallel = true
			}
			'-native' {
				res.backend = .native
				res.build_options << arg
			}
			'-interpret' {
				res.backend = .interpret
			}
			'-W' {
				res.warns_are_errors = true
			}
			'-no-rsp' {
				res.no_rsp = true
			}
			'-no-std' {
				res.no_std = true
			}
			'-keepc' {
				res.reuse_tmpc = true
			}
			'-w' {
				res.skip_warnings = true
			}
			'-watch' {
				eprintln('The -watch option is deprecated. Please use the watch command `v watch file.v` instead.')
				exit(1)
			}
			'-print-v-files' {
				res.print_v_files = true
			}
			'-os' {
				target_os := cmdline.option(current_args, '-os', '')
				i++
				target_os_kind := os_from_string(target_os) or {
					if target_os == 'cross' {
						res.output_cross_c = true
						continue
					}
					eprintln('unknown operating system target `$target_os`')
					exit(1)
				}
				if target_os_kind == .wasm32 {
					res.is_bare = true
				}
				res.os = target_os_kind
				res.build_options << '$arg $target_os'
			}
			'-printfn' {
				res.printfn_list << cmdline.option(current_args, '-printfn', '').split(',')
				i++
			}
			'-cflags' {
				res.cflags += ' ' + cmdline.option(current_args, '-cflags', '')
				res.build_options << '$arg "$res.cflags.trim_space()"'
				i++
			}
			'-d', '-define' {
				if current_args.len > 1 {
					define := current_args[1]
					res.parse_define(define)
				}
				i++
			}
			'-error-limit', '-message-limit' {
				res.message_limit = cmdline.option(current_args, arg, '5').int()
				i++
			}
			'-cc' {
				res.ccompiler = cmdline.option(current_args, '-cc', 'cc')
				res.build_options << '$arg "$res.ccompiler"'
				i++
			}
			'-checker-match-exhaustive-cutoff-limit' {
				res.checker_match_exhaustive_cutoff_limit = cmdline.option(current_args,
					arg, '10').int()
				i++
			}
			'-o', '-output' {
				res.out_name = cmdline.option(current_args, arg, '')
				if res.out_name.ends_with('.js') {
					res.backend = .js_node
					res.output_cross_c = true
				} else if res.out_name.ends_with('.o') {
					res.is_o = true
				}
				if !os.is_abs_path(res.out_name) {
					res.out_name = os.join_path(os.getwd(), res.out_name)
				}
				i++
			}
			'-b', '-backend' {
				sbackend := cmdline.option(current_args, arg, 'c')
				res.build_options << '$arg $sbackend'
				b := backend_from_string(sbackend) or { continue }
				if b.is_js() {
					res.output_cross_c = true
				}
				res.backend = b
				i++
			}
			'-es5' {
				res.output_es5 = true
			}
			'-path' {
				path := cmdline.option(current_args, '-path', '')
				res.build_options << '$arg "$path"'
				res.lookup_path = path.replace('|', os.path_delimiter).split(os.path_delimiter)
				i++
			}
			'-bare-builtin-dir' {
				bare_builtin_dir := cmdline.option(current_args, arg, '')
				res.build_options << '$arg "$bare_builtin_dir"'
				res.bare_builtin_dir = bare_builtin_dir
				i++
			}
			'-custom-prelude' {
				path := cmdline.option(current_args, '-custom-prelude', '')
				res.build_options << '$arg $path'
				prelude := os.read_file(path) or {
					eprintln('cannot open custom prelude file: $err')
					exit(1)
				}
				res.custom_prelude = prelude
				i++
			}
			else {
				if command == 'build' && is_source_file(arg) {
					eprintln('Use `v $arg` instead.')
					exit(1)
				}
				if arg[0] == `-` {
					if arg[1..] in pref.list_of_flags_with_param {
						// skip parameter
						i++
						continue
					}
				} else {
					if command == '' {
						command = arg
						command_pos = i
						if command == 'run' {
							break
						}
					} else if is_source_file(command) && is_source_file(arg)
						&& command !in known_external_commands {
						eprintln('Too many targets. Specify just one target: <target.v|target_directory>.')
						exit(1)
					}
					continue
				}
				if arg in ['-V', '-version', '--version'] {
					command = 'version'
					command_pos = i
					continue
				}
				if command != '' && command != 'build-module' {
					// arguments for e.g. fmt should be checked elsewhere
					continue
				}
				extension := if command.len == 0 { '' } else { ' for command `$command`' }
				eprintln('Unknown argument `$arg`$extension')
				exit(1)
			}
		}
	}
	if res.is_debug {
		res.parse_define('debug')
	}
	if command == 'run' && res.is_prod && os.is_atty(1) > 0 {
		eprintln_cond(show_output, "NB: building an optimized binary takes much longer. It shouldn't be used with `v run`.")
		eprintln_cond(show_output, 'Use `v run` without optimization, or build an optimized binary with -prod first, then run it separately.')
	}

	// res.use_cache = true
	if command != 'doc' && res.out_name.ends_with('.v') {
		eprintln('Cannot save output binary in a .v file.')
		exit(1)
	}
	if command == 'run' {
		res.is_run = true
		if command_pos + 2 > args.len {
			eprintln('v run: no v files listed')
			exit(1)
		}
		res.path = args[command_pos + 1]
		res.run_args = args[command_pos + 2..]
		if res.path == '-' {
			tmp_file_path := rand.ulid()
			mut tmp_exe_file_path := res.out_name
			mut output_option := ''
			if tmp_exe_file_path == '' {
				tmp_exe_file_path = '${tmp_file_path}.exe'
				output_option = '-o ${os.quoted_path(tmp_exe_file_path)} '
			}
			tmp_v_file_path := '${tmp_file_path}.v'
			contents := os.get_raw_lines_joined()
			os.write_file(tmp_v_file_path, contents) or {
				panic('Failed to create temporary file $tmp_v_file_path')
			}
			run_options := cmdline.options_before(args, ['run']).join(' ')
			command_options := cmdline.options_after(args, ['run'])[1..].join(' ')
			vexe := vexe_path()
			tmp_cmd := '${os.quoted_path(vexe)} $output_option $run_options run ${os.quoted_path(tmp_v_file_path)} $command_options'
			//
			res.vrun_elog('tmp_cmd: $tmp_cmd')
			tmp_result := os.system(tmp_cmd)
			res.vrun_elog('exit code: $tmp_result')
			//
			if output_option.len != 0 {
				res.vrun_elog('remove tmp exe file: $tmp_exe_file_path')
				os.rm(tmp_exe_file_path) or {}
			}
			res.vrun_elog('remove tmp v file: $tmp_v_file_path')
			os.rm(tmp_v_file_path) or {}
			exit(tmp_result)
		}
		must_exist(res.path)
		if !res.path.ends_with('.v') && os.is_executable(res.path) && os.is_file(res.path)
			&& os.is_file(res.path + '.v') {
			eprintln_cond(show_output, 'It looks like you wanted to run "${res.path}.v", so we went ahead and did that since "$res.path" is an executable.')
			res.path += '.v'
		}
	} else if is_source_file(command) {
		res.path = command
	}
	if !res.is_bare && res.bare_builtin_dir != '' {
		eprintln_cond(show_output, '`-bare-builtin-dir` must be used with `-freestanding`')
	}
	if command.ends_with('.vsh') {
		// `v build.vsh gcc` is the same as `v run build.vsh gcc`,
		// i.e. compiling, then running the script, passing the args
		// after it to the script:
		res.is_run = true
		res.path = command
		res.run_args = args[command_pos + 1..]
	} else if command == 'interpret' {
		res.backend = .interpret
		if command_pos + 2 > args.len {
			eprintln('v interpret: no v files listed')
			exit(1)
		}
		res.path = args[command_pos + 1]
		res.run_args = args[command_pos + 2..]

		must_exist(res.path)
		if !res.path.ends_with('.v') && os.is_executable(res.path) && os.is_file(res.path)
			&& os.is_file(res.path + '.v') {
			eprintln('It looks like you wanted to run "${res.path}.v", so we went ahead and did that since "$res.path" is an executable.')
			res.path += '.v'
		}
	}
	if command == 'build-module' {
		res.build_mode = .build_module
		if command_pos + 1 >= args.len {
			eprintln('v build-module: no module specified')
			exit(1)
		}
		res.path = args[command_pos + 1]
	}
	// keep only the unique res.build_options:
	mut m := map[string]string{}
	for x in res.build_options {
		m[x] = ''
	}
	res.build_options = m.keys()
	// eprintln('>> res.build_options: $res.build_options')
	res.fill_with_defaults()
	return res, command
}

pub fn eprintln_cond(condition bool, s string) {
	if !condition {
		return
	}
	eprintln(s)
}

pub fn (pref &Preferences) vrun_elog(s string) {
	if pref.is_verbose {
		eprintln('> v run -, $s')
	}
}

pub fn (pref &Preferences) should_output_to_stdout() bool {
	return pref.out_name.ends_with('/-') || pref.out_name.ends_with(r'\-')
}

pub fn arch_from_string(arch_str string) ?Arch {
	match arch_str {
		'amd64', 'x86_64', 'x64', 'x86' { // amd64 recommended

			return Arch.amd64
		}
		'aarch64', 'arm64' { // arm64 recommended

			return Arch.arm64
		}
		'aarch32', 'arm32', 'arm' { // arm32 recommended

			return Arch.arm32
		}
		'rv64', 'riscv64', 'risc-v64', 'riscv', 'risc-v' { // rv64 recommended

			return Arch.rv64
		}
		'rv32', 'riscv32' { // rv32 recommended

			return Arch.rv32
		}
		'x86_32', 'x32', 'i386', 'IA-32', 'ia-32', 'ia32' { // i386 recommended

			return Arch.i386
		}
		'js', 'js_node' {
			return Arch.js_node
		}
		'js_browser' {
			return Arch.js_browser
		}
		'js_freestanding' {
			return Arch.js_freestanding
		}
		'' {
			return ._auto
		}
		else {
			return error('invalid arch: $arch_str')
		}
	}
}

fn must_exist(path string) {
	if !os.exists(path) {
		eprintln('v expects that `$path` exists, but it does not')
		exit(1)
	}
}

[inline]
fn is_source_file(path string) bool {
	return path.ends_with('.v') || os.exists(path)
}

pub fn backend_from_string(s string) ?Backend {
	match s {
		'c' { return .c }
		'js' { return .js_node }
		'js_node' { return .js_node }
		'js_browser' { return .js_browser }
		'js_freestanding' { return .js_freestanding }
		'native' { return .native }
		'interpret' { return .interpret }
		else { return error('Unknown backend type $s') }
	}
}

// Helper function to convert string names to CC enum
pub fn cc_from_string(cc_str string) CompilerType {
	if cc_str.len == 0 {
		return .gcc
	}
	// TODO
	normalized_cc := cc_str.replace('\\', '/')
	normalized_cc_array := normalized_cc.split('/')
	last_elem := normalized_cc_array.last()
	cc := last_elem.all_before('.')
	if cc.contains('++') {
		return .cplusplus
	}
	if cc.contains('tcc') || cc.contains('tinyc') {
		return .tinyc
	}
	if cc.contains('clang') {
		return .clang
	}
	if cc.contains('mingw') {
		return .mingw
	}
	if cc.contains('msvc') {
		return .msvc
	}
	return .gcc
}

pub fn get_host_arch() Arch {
	// NB: we can not use `$if arch` here, because V skips cgen for the non
	// current comptime branches by default, so there is a bootstrapping
	// problem => the __V_architecture macro is used to resolve it.
	// TODO: think about how to solve it for non C backends, perhaps we
	// need a comptime `$if native {` too, and/or a mechanism to always
	// generate all branches for specific functions?
	if C.__V_architecture <= int(Arch._auto) || C.__V_architecture >= int(Arch._max) {
		return Arch.amd64
	}
	return Arch(C.__V_architecture)
}

fn (mut prefs Preferences) parse_define(define string) {
	define_parts := define.split('=')
	if !(prefs.is_debug && define == 'debug') {
		prefs.build_options << '-d $define'
	}
	if define_parts.len == 1 {
		prefs.compile_defines << define
		prefs.compile_defines_all << define
		return
	}
	if define_parts.len == 2 {
		prefs.compile_defines_all << define_parts[0]
		match define_parts[1] {
			'0' {}
			'1' {
				prefs.compile_defines << define_parts[0]
			}
			else {
				println(
					'V error: Unknown define argument value `${define_parts[1]}` for ${define_parts[0]}.' +
					' Expected `0` or `1`.')
				exit(1)
			}
		}
		return
	}
	println('V error: Unknown define argument: ${define}. Expected at most one `=`.')
	exit(1)
}
