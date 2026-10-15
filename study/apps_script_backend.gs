/**
 * PostureGuard study — participant onboarding backend.
 *
 * Receives one submission from participant_onboarding.html, assigns the
 * counterbalanced condition order, and appends a row to the bound Sheet.
 *
 * Study design: counterbalanced crossover. Every participant uses both
 * feedback versions, one after the other. Half start with A, half start
 * with B, so that any learning effect from the first phase is spread
 * evenly across both arms instead of favouring whichever came second.
 *
 * Deploy: Extensions → Apps Script in the target Sheet, paste this file,
 * then Deploy → New deployment → Web app, "Execute as: Me",
 * "Who has access: Anyone". Copy the /exec URL into ENDPOINT in the HTML.
 * See study/README.md for the full walkthrough.
 */

/** Sheet tab that receives submissions. Created automatically if absent. */
var SHEET_NAME = 'participants';

/**
 * Column order. The first three are produced here, not by the form.
 * Adding a question to the form means adding its `name` to this list —
 * nothing else needs to change.
 */
var COLUMNS = [
  'user_id',
  'sequence',        // 'AB' or 'BA' — which version the participant starts with
  'phase1_variant',  // derived from sequence, for convenience when filtering
  'phase2_variant',
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
  // moment must not read the same arm counts and both get variant A.
  try {
    lock.waitLock(30000);
  } catch (err) {
    return json({ ok: false, error: 'busy' });
  }

  try {
    var record = JSON.parse(e.postData.contents);

    if (!record.user_id) {
      return json({ ok: false, error: 'missing user_id' });
    }

    var sheet = getSheet();

    if (findRowByUserId(sheet, record.user_id) > 0) {
      // Should never happen at this ID length, but a silent overwrite
      // would be worse than a refusal.
      return json({ ok: false, error: 'duplicate user_id' });
    }

    record.sequence = assignSequence(sheet);
    record.phase1_variant = record.sequence.charAt(0);
    record.phase2_variant = record.sequence.charAt(1);
    record.received_at = new Date().toISOString();

    sheet.appendRow(COLUMNS.map(function (key) {
      var value = record[key];
      return (value === undefined || value === null) ? '' : String(value);
    }));

    return json({ ok: true, sequence: record.sequence });

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
 * Counterbalancing: whichever starting order currently has fewer
 * participants wins, ties broken at random.
 *
 * This is what makes the crossover design valid. Both versions teach
 * posture awareness, so a participant is simply better at sitting by the
 * time the second phase starts. Splitting the starting order evenly means
 * that improvement lands on A and B equally, instead of inflating whichever
 * version everyone happened to use second.
 *
 * Counting live rows rather than keeping a counter means the split stays
 * balanced even if someone abandons the form halfway, and it stays correct
 * if you delete a test row.
 */
function assignSequence(sheet) {
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) {
    return Math.random() < 0.5 ? 'AB' : 'BA';
  }

  var col = COLUMNS.indexOf('sequence') + 1;
  var values = sheet.getRange(2, col, lastRow - 1, 1).getValues();

  var ab = 0, ba = 0;
  for (var i = 0; i < values.length; i++) {
    if (values[i][0] === 'AB') ab++;
    else if (values[i][0] === 'BA') ba++;
  }

  if (ab < ba) return 'AB';
  if (ba < ab) return 'BA';
  return Math.random() < 0.5 ? 'AB' : 'BA';
}

function findRowByUserId(sheet, userId) {
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return -1;
  var ids = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  for (var i = 0; i < ids.length; i++) {
    if (ids[i][0] === userId) return i + 2;
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
  return sheet;
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Run this once from the Apps Script editor to confirm the Sheet is
 * writable and the allocation works, then delete the two test rows.
 */
function selfTest() {
  var sheet = getSheet();
  Logger.log('Sheet ready: %s, rows: %s', sheet.getName(), sheet.getLastRow());
  Logger.log('Next assignment would be: %s', assignSequence(sheet));
}

/**
 * Current counterbalance — run from the editor during recruitment to check
 * the split without opening the Sheet.
 */
function groupCounts() {
  var sheet = getSheet();
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) { Logger.log('No participants yet.'); return; }
  var col = COLUMNS.indexOf('sequence') + 1;
  var values = sheet.getRange(2, col, lastRow - 1, 1).getValues();
  var ab = 0, ba = 0;
  values.forEach(function (r) {
    if (r[0] === 'AB') ab++; else if (r[0] === 'BA') ba++;
  });
  Logger.log('Starting with A (AB): %s participants', ab);
  Logger.log('Starting with B (BA): %s participants', ba);
  Logger.log('Total: %s', ab + ba);
}
