using System;
using System.ComponentModel.DataAnnotations;

namespace NutritionBI.Web.Models
{
    public class MiningInputModel
    {
        [Display(Name = "Calories (kcal)")]
        public double Calories { get; set; } = 450;

        [Display(Name = "Protein (PDV%)")]
        public double Protein_PDV { get; set; } = 25;

        [Display(Name = "Carbs (PDV%)")]
        public double Carbs_PDV { get; set; } = 50;

        [Display(Name = "Total Fat (PDV%)")]
        public double TotalFat_PDV { get; set; } = 15;

        [Display(Name = "Sugar (PDV%)")]
        public double Sugar_PDV { get; set; } = 10;

        [Display(Name = "Sodium (PDV%)")]
        public double Sodium_PDV { get; set; } = 10;

        [Display(Name = "Là món ăn chay?")]
        public int IsVegetarian { get; set; } = 0;   // 0 = Không, 1 = Có

        [Display(Name = "Thời gian nấu (phút)")]
        public int Minutes { get; set; } = 30;
        
        [Display(Name = "Số lượng nguyên liệu")]
        public int N_Ingredients { get; set; } = 5;

        // Có thể thêm sau này nếu cần
        // public double SatFat_PDV { get; set; }
    }

    public class MiningResultModel
    {
        // Rating Prediction
        public string PredictedRating { get; set; }
        public double DtConfidence { get; set; }

        // Clustering
        public string ClusterLabel { get; set; }
        public string ClusterEmoji { get; set; }

        // Healthy Prediction
        public bool IsHealthy { get; set; }
        public double HealthyProbability { get; set; }

        // Thông báo lỗi (dùng khi cần)
        public string ErrorMessage { get; set; }
    }
}