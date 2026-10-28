using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using System;

public static class UnityBootstrap
{
    private const string ScenePath = "Assets/Scenes/VoxelPatrol.unity";

    [InitializeOnLoadMethod]
    private static void EnsureDefaultScene()
    {
        EditorApplication.delayCall += () =>
        {
            if (!File.Exists(ScenePath))
                GenerateProject();
        };
    }

    [MenuItem("Megyejaror/Generate Voxel Patrol Scene")]
    public static void GenerateProject()
    {
        Directory.CreateDirectory("Assets/Scenes");
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var gameObject = new GameObject("Megyejaror Voxel Game");
        gameObject.AddComponent<MegyejarorGame>();
        EditorSceneManager.SaveScene(gameObject.scene, ScenePath);
        EditorBuildSettings.scenes = new[]
        {
            new EditorBuildSettingsScene(ScenePath, true)
        };
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("Generated the Megyejaror voxel gameplay scene.");
    }

    public static void ValidateProject()
    {
        var dataAsset = AssetDatabase.LoadAssetAtPath<TextAsset>("Assets/Resources/counties.json");
        if (dataAsset == null)
            throw new InvalidOperationException("The county map resource is missing.");

        CountyDataFile data = JsonUtility.FromJson<CountyDataFile>(dataAsset.text);
        if (data == null || data.counties == null || data.counties.Length != 19)
            throw new InvalidOperationException("Expected 19 counties in the Unity map data.");

        foreach (CountyData county in data.counties)
        {
            if (string.IsNullOrWhiteSpace(county.name) || string.IsNullOrWhiteSpace(county.seat)
                || county.points == null || county.points.Length < 6 || county.points.Length % 2 != 0)
                throw new InvalidOperationException("Invalid county record: " + county.id);
        }

        if (!File.Exists(ScenePath))
            GenerateProject();
        Scene scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        bool hasGame = false;
        foreach (GameObject root in scene.GetRootGameObjects())
        {
            if (root.GetComponent<MegyejarorGame>() != null)
                hasGame = true;
        }
        if (!hasGame)
            throw new InvalidOperationException("The generated gameplay scene is missing its game controller.");

        Debug.Log("Unity project validation passed: 19 county polygons and a gameplay scene.");
    }

    [MenuItem("Megyejaror/Build Windows Game")]
    public static void BuildWindowsGame()
    {
        if (!File.Exists(ScenePath))
            GenerateProject();
        Directory.CreateDirectory("Build");
        var options = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = "Build/Megyejaror.exe",
            target = BuildTarget.StandaloneWindows64
        };
        BuildReport report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
            throw new InvalidOperationException("Windows game build failed: " + report.summary.result);
        Debug.Log("Built the Megyejaror voxel game: " + report.summary.outputPath);
    }
}
