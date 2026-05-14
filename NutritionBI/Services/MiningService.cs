using Microsoft.AnalysisServices.AdomdClient;
using NutritionBI.Web.Models;
using System;
using System.Configuration;

namespace NutritionBI.Web.Services
{
    public class MiningService
    {
        private readonly string _connStr = ConfigurationManager.ConnectionStrings["SsasConn"].ConnectionString;

        // 1. Dự đoán Rating
        public MiningResultModel GetRatingPrediction(MiningInputModel input)
        {
            var res = new MiningResultModel();
            try
            {
                using (var conn = new AdomdConnection(_connStr))
                {
                    conn.Open();

                    string dmx = $@"
                        SELECT
                            Predict([Rating Category]) AS [PredictedRating],
                            PredictProbability([Rating Category]) AS [Probability]
                        FROM [V Decision Tree High Accuracy]
                        NATURAL PREDICTION JOIN
                        (SELECT {input.Calories} AS [Calories],
                                 {input.Protein_PDV} AS [Protein_PDV],
                                 {input.TotalFat_PDV} AS [TotalFat_PDV],
                                 {input.Sugar_PDV} AS [Sugar_PDV],
                                 {input.Sodium_PDV} AS [Sodium_PDV],
                                 {input.Carbs_PDV} AS [Carbs_PDV],
                                 {input.Minutes} AS [Minutes],
                                 {input.N_Ingredients} AS [N_ingredients],
                                 {input.IsVegetarian} AS [IsVegetarian]) AS [t]";

                    using (var cmd = new AdomdCommand(dmx, conn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read())
                        {
                            res.PredictedRating = dr.GetValue(0)?.ToString()?.Trim();
                            res.DtConfidence = Convert.ToDouble(dr.GetValue(1));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                throw new Exception("Lỗi dự đoán rating: " + ex.Message);
            }
            return res;
        }

        // 2. Phân cụm
        public MiningResultModel GetClusterGroup(MiningInputModel input)
        {
            var res = new MiningResultModel();
            try
            {
                using (var conn = new AdomdConnection(_connStr))
                {
                    conn.Open();

                    string dmx = $@"
                        SELECT Cluster() AS [ClusterId]
                        FROM [Recipe Clustering]
                        NATURAL PREDICTION JOIN
                        (SELECT {input.TotalFat_PDV} AS [TotalFat_PDV],
                                {input.Sugar_PDV} AS [Sugar_PDV],
                                {input.Calories} AS [Calories]) AS [t]";

                    using (var cmd = new AdomdCommand(dmx, conn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read())
                        {
                            string clusterId = dr.GetValue(0)?.ToString();
                            res.ClusterLabel = MapLabel(clusterId);
                            res.ClusterEmoji = MapEmoji(res.ClusterLabel);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                throw new Exception("Lỗi phân cụm: " + ex.Message);
            }
            return res;
        }

        // 3. Độ lành mạnh
        public MiningResultModel GetHealthStatus(MiningInputModel input)
        {
            var res = new MiningResultModel();
            try
            {
                using (var conn = new AdomdConnection(_connStr))
                {
                    conn.Open();

                    // Đã loại bỏ IsVegetarian khỏi câu lệnh DMX
                    string dmx = $@"
                SELECT
                    Predict([Is Healthy]) AS [Is Healthy],
                    PredictProbability([Is Healthy], 1) AS [Probability]
                 FROM [Healthy Recipe Logistic Reg]
                NATURAL PREDICTION JOIN
                (SELECT {input.Sodium_PDV} AS [Sodium_PDV],
                        {input.TotalFat_PDV} AS [TotalFat_PDV],
                        {input.Sugar_PDV} AS [Sugar_PDV]) AS [t]";

                    using (var cmd = new AdomdCommand(dmx, conn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read())
                        {
                            res.IsHealthy = Convert.ToBoolean(dr.GetValue(0));
                            res.HealthyProbability = Convert.ToDouble(dr.GetValue(1));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                throw new Exception("Lỗi kiểm tra độ lành mạnh: " + ex.Message);
            }
            return res;
        }

        private string MapLabel(string clusterId)
        {
            switch (clusterId?.Trim())
            {
                case "Cluster 1": return "Protein Powerhouse";
                case "Cluster 2": return "Light & Fresh";
                case "Cluster 3": return "Carb Heavy";
                default: return "Balanced Mix";
            }
        }

        private string MapEmoji(string label)
        {
            switch (label)
            {
                case "Protein Powerhouse": return "💪";
                case "Light & Fresh": return "🥗";
                case "Carb Heavy": return "🍞";
                default: return "🍽️";
            }
        }
    }
}