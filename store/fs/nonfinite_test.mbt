///|
async test "read zarr-python non-finite fill fixtures" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_f64_nan.zarr") is Some(v2_store) else {
    fail("v2 NaN fixture store")
  }
  guard v2_store.open_f64("") is Some(v2_array) else {
    fail("v2 NaN fixture array")
  }
  guard v2_array.read([0]) is Some(missing_nan) else { fail("v2 missing NaN") }
  assert_true(missing_nan.is_nan())
  assert_eq(v2_array.read([2]), Some(42.25))

  guard @fs.FileStore::new("\{base}/v3_f32_neg_inf.zarr") is Some(v3_store) else {
    fail("v3 infinity fixture store")
  }
  guard v3_store.open_f32("") is Some(v3_array) else {
    fail("v3 infinity fixture array")
  }
  assert_eq(v3_array.read([0]), Some(Float::reinterpret_from_uint(0xFF800000U)))
  assert_eq(v3_array.read([2]), Some(1.25))
}
