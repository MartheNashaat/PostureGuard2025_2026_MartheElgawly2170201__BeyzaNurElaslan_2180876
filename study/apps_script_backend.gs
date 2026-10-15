/**
 * PostureGuard study — participant onboarding backend.
 *
 * Receives one submission from participant_onboarding.html, checks the
 * participant ID, and appends a row to the bound Sheet.
 *
 * Study design: each participant chooses one feedback version (A or B) in
 * the app and uses only that one, so nothing is assigned here. The version
 * arrives with each uploaded session as `variant`.
 *
 * Deploy: Extensions → Apps Script in the target Sheet, paste this file,
 * then Deploy → New deployment → Web app, "Execute as: Me",
 * "Who has access: Anyone". Copy the /exec URL into ENDPOINT in the HTML.
 * See study/README.md for the full walkthrough.
 */

/** Sheet tab that receives submissions. Created automatically if absent. */
var SHEET_NAME = 'participants';

/**
 * Participant ID rule — must match ParticipantService in the app
 * (lib/services/participant_service.dart): at least 6 letters/numbers,
 * kept exactly as typed. 20 is the app's input field limit.
 */
var USER_ID_PATTERN = /^[A-Za-z0-9]{6,20}$/;

/**
 * Column order. `received_at` is produced here, not by the form.
 * Adding a question to the form means adding its `name` to this list —
 * nothing else needs to change.
 */
var COLUMNS = [
  'user_id',
  'received_at',
  'submitted_at',
  'form_version',

  // Consent
  'consent_read',
  'consent_camera',
  'consent_upload',
  'consent_pseudonymous',
  'consent_withdraw',
  'consent_age',
  'consent_voluntary',
  'consent_followup',
  'consent_future',
  'consent_quotes',

  // Identity (the restricted linking list)
  'full_name',
  'email',
  'signature',
  'signed_date',

  // Demographics
  'age',
  'occupation',
  'screen_total',
  'screen_phone',
  'pain_freq',
  'pain_area',
  'pain_now',
  'pain_treatment',
  'desk_setup',
  'chair',
  'monitor_height',
  'phone_hold',
  'posture_aware',

  // Device
  'phone_model',
  'android_version'
];

/**
 * Web app entry point.
 *
 * Always returns JSON. The form treats any non-{ok:true} answer as a
 * failure and shows the participant a manual-copy fallback, so a thrown
 * error here never costs a participant their responses.
 */
function doPost(e) {
  var lock = LockService.getScriptLock();

  // Serialise submissions: two people finishing the form at the same
  // moment must not both pass the duplicate-ID check with the same ID.
  try {
    lock.waitLock(30000);
  } catch (err) {
    return json({ ok: false, error: 'busy' });
  }

  try {
    var record = JSON.parse(e.postData.contents);

    record.user_id = String(record.user_id || '').trim();
    if (!USER_ID_PATTERN.test(record.user_id)) {
      return json({ ok: false, error: 'invalid user_id' });
    }

    var sheet = getSheet();

    if (findRowByUserId(sheet, record.user_id) > 0) {
      // Participants choose their own ID, so this does happen. The form
      // asks them to pick another one.
      return json({ ok: false, error: 'duplicate user_id' });
    }

    record.received_at = new Date().toISOString();

    sheet.appendRow(COLUMNS.map(function (key) {
      var value = record[key];
      return (value === undefined || value === null) ? '' : String(value);
    }));

    return json({ ok: true });

  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/** Browsing to the /exec URL should say something useful, not error. */
function doGet() {
  return json({ ok: true, service: 'postureguard-onboarding' });
}

/**
 * Case-insensitive on purpose. The app treats `ab12cd` and `AB12CD` as
 * different IDs, but two participants that close would be easy to mix up
 * when joining sessions to consent records, so the form refuses the second.
 */
function findRowByUserId(sheet, userId) {
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return -1;
  var wanted = userId.toLowerCase();
  var ids = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  for (var i = 0; i < ids.length; i++) {
    if (String(ids[i][0]).toLowerCase() === wanted) return i + 2;
  }
  return -1;
}

function getSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(COLUMNS);
    sheet.getRange(1, 1, 1, COLUMNS.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
  }
  // Plain text, so an all-digit ID like `001234` isn't turned into the
  // number 1234 and stops matching the app's sessions.
  sheet.getRange('A:A').setNumberFormat('@');
  return sheet;
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Run this once from the Apps Script editor to authorise the script and
 * confirm the Sheet is writable.
 */
function selfTest() {
  var sheet = getSheet();
  Logger.log('Sheet ready: %s, rows: %s', sheet.getName(), sheet.getLastRow());
}
