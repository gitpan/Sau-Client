use Module::Build;
Module::Build->new(
		   module_name => 'Sau::Client',
		   license => 'open_source',
		   dist_version_from => 'Client.pm',
		   pm_files => { 'Client.pm' => 'lib/Sau/Client.pm' },
		   create_readme => 1,
		   create_makefile_pl => 'traditional',
		   requires => {
				'Cache::Cache'    => '1.02',
				'LWP::UserAgent'  => 0,
				'XML::Simple'     => '2.12',
				'URI::Escape'     => 0,
				'Digest::SHA1'    => 0,
			       },
		   build_requires => {
				      'Test::WWW::Mechanize' => 0,
				     },
		   sign => 1,
		   dist_author => 'Ask Bjoern Hansen <ask@develooper.com>',
)->create_build_script;


