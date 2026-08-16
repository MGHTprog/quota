using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;

namespace Quota.Windows
{
    internal static class Json
    {
        private static readonly JavaScriptSerializer Serializer = new JavaScriptSerializer
        {
            MaxJsonLength = 4 * 1024 * 1024,
            RecursionLimit = 100
        };

        public static object Parse(string text) { return Serializer.DeserializeObject(text); }
        public static string Stringify(object value) { return Serializer.Serialize(value); }

        public static IDictionary<string, object> Object(object value)
        {
            return value as IDictionary<string, object>;
        }

        public static object Get(object value, string key)
        {
            var map = Object(value);
            if (map == null) return null;
            object result;
            return map.TryGetValue(key, out result) ? result : null;
        }

        public static string Text(object value, string key)
        {
            var raw = Get(value, key);
            return raw == null ? null : Convert.ToString(raw, CultureInfo.InvariantCulture);
        }

        public static double? Number(object value, string key)
        {
            var raw = Get(value, key);
            if (raw == null) return null;
            double number;
            return double.TryParse(Convert.ToString(raw, CultureInfo.InvariantCulture), NumberStyles.Any,
                CultureInfo.InvariantCulture, out number) ? (double?)number : null;
        }

        public static object[] Array(object value, string key)
        {
            var raw = Get(value, key);
            if (raw is object[]) return (object[])raw;
            var list = raw as ArrayList;
            return list == null ? new object[0] : list.ToArray();
        }

        public static DateTime? Date(object value, string key)
        {
            var raw = Get(value, key);
            if (raw == null) return null;

            double epoch;
            if (double.TryParse(Convert.ToString(raw, CultureInfo.InvariantCulture), NumberStyles.Any,
                CultureInfo.InvariantCulture, out epoch))
            {
                return DateTimeOffset.FromUnixTimeSeconds((long)epoch).LocalDateTime;
            }

            DateTimeOffset parsed;
            return DateTimeOffset.TryParse(Convert.ToString(raw, CultureInfo.InvariantCulture),
                CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out parsed)
                ? (DateTime?)parsed.LocalDateTime
                : null;
        }

        public static bool? Bool(object value, string key)
        {
            var raw = Get(value, key);
            if (raw == null) return null;
            if (raw is bool) return (bool)raw;
            bool result;
            return bool.TryParse(Convert.ToString(raw, CultureInfo.InvariantCulture), out result) ? (bool?)result : null;
        }
    }
}
