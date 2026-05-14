using System;
using System.Web.Mvc;
using NutritionBI.Web.Models;
using NutritionBI.Web.Services;

namespace NutritionBI.Web.Controllers
{
    public class PredictController : Controller
    {
        private readonly MiningService _service;

        public PredictController()
        {
            _service = new MiningService();
        }

        // GET: Views
        public ActionResult Rating() => View();
        public ActionResult Clusters() => View();
        public ActionResult Healthy() => View();

        [HttpPost]
        public JsonResult AnalyzeRating(MiningInputModel input)
        {
            try
            {
                if (input == null)
                    return Json(new { success = false, message = "Dữ liệu đầu vào không hợp lệ" });

                var result = _service.GetRatingPrediction(input);
                return Json(new { success = true, data = result });
            }
            catch (Exception ex)
            {
                // Log lỗi nếu có logger
                return Json(new { success = false, message = "Lỗi khi dự đoán rating: " + ex.Message });
            }
        }

        [HttpPost]
        public JsonResult AnalyzeCluster(MiningInputModel input)
        {
            try
            {
                if (input == null)
                    return Json(new { success = false, message = "Dữ liệu đầu vào không hợp lệ" });

                var result = _service.GetClusterGroup(input);
                return Json(new { success = true, data = result });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Lỗi khi phân cụm: " + ex.Message });
            }
        }

        [HttpPost]
        public JsonResult AnalyzeHealthy(MiningInputModel input)
        {
            try
            {
                if (input == null)
                    return Json(new { success = false, message = "Dữ liệu đầu vào không hợp lệ" });

                var result = _service.GetHealthStatus(input);
                return Json(new { success = true, data = result });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Lỗi khi phân tích sức khỏe: " + ex.Message });
            }
        }
    }
}