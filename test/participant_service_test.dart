import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/services/participant_service.dart';

void main() {
  test('6 or more letters/numbers are accepted exactly as typed', () {
    expect(ParticipantService.normalize('ab12cd'), 'ab12cd');
    expect(ParticipantService.normalize('AB12CD'), 'AB12CD');
    expect(ParticipantService.normalize('  Marthe01 '), 'Marthe01');
    expect(ParticipantService.normalize('abcdef'), 'abcdef');
    expect(ParticipantService.normalize('123456'), '123456');
  });

  test('shorter than 6 is rejected', () {
    expect(ParticipantService.normalize(''), isNull);
    expect(ParticipantService.normalize('ab12c'), isNull);
    expect(ParticipantService.normalize('   abc   '), isNull);
  });

  test('spaces and symbols inside are rejected', () {
    for (final bad in ['ab 12cd', 'ab-12cd', 'PG-E8XM-H06Y', 'abc12!', 'ab_cdef']) {
      expect(ParticipantService.normalize(bad), isNull, reason: bad);
      expect(ParticipantService.hasInvalidCharacters(bad), isTrue, reason: bad);
    }
  });

  test('short but clean input is not flagged as invalid characters', () {
    expect(ParticipantService.hasInvalidCharacters('ab1'), isFalse);
    expect(ParticipantService.hasInvalidCharacters(''), isFalse);
  });
}
