use Test2::Require::Module 'Importer';
use Test2::V0 -no_srand => 1;
use Importer 'Test2::Tools::HTTP' => ':short';

imported_ok 'ua';
imported_ok 'res';
imported_ok 'req';

done_testing;
