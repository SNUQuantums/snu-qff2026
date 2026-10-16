// Local TEST-MODE config. Copy this file to assets/supabase-config.local.js
// (that name is gitignored). Pages served from localhost / 127.0.0.1 load it
// before supabase-config.js, so every call goes to the qff_test_* tables and a
// red TEST MODE ribbon appears. Never deploy this file.
window.QFF_SUPABASE_CONFIG = {
  testMode: true,
  url: "https://ezebbyoxohgouodwvbfv.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV6ZWJieW94b2hnb3VvZHd2YmZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzMTg4MjEsImV4cCI6MjEwNTg5NDgyMX0.WfLKHLMDpRjaKkFhbi_pGpN215pCxl4jZK3md55kIsE",
};
