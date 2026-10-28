using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[Serializable]
public sealed class CountyDataFile
{
    public CountyData[] counties;
}

[Serializable]
public sealed class CountyData
{
    public string id;
    public string name;
    public string seat;
    public float seat_x;
    public float seat_y;
    public float[] points;
}

public sealed class MegyejarorGame : MonoBehaviour
{
    private const float MapScale = 0.038f;
    private const float MapCenterX = 380f;
    private const float MapCenterY = 230f;
    private const float GridStep = 10f;
    private const float BlockHeight = 0.32f;
    private const int MaximumLives = 3;

    private static readonly Color[] CountyPalette =
    {
        new Color(0.75f, 0.62f, 0.40f),
        new Color(0.42f, 0.67f, 0.63f),
        new Color(0.83f, 0.52f, 0.36f),
        new Color(0.56f, 0.66f, 0.38f),
        new Color(0.69f, 0.56f, 0.75f),
        new Color(0.82f, 0.69f, 0.39f)
    };

    private static readonly Color LearnedColor = new Color(0.29f, 0.69f, 0.42f);
    private static readonly Color SoldierGreen = new Color(0.28f, 0.43f, 0.22f);
    private static readonly string[] EnemyNames = { "árnylovag", "vadkan", "sárkány" };
    private static readonly Color[] EnemyColors =
    {
        new Color(0.42f, 0.31f, 0.36f),
        new Color(0.54f, 0.36f, 0.23f),
        new Color(0.22f, 0.48f, 0.35f)
    };
    private static Shader voxelShader;

    private readonly List<CountyData> counties = new List<CountyData>();
    private readonly List<CountyData> roundQueue = new List<CountyData>();
    private readonly HashSet<string> learned = new HashSet<string>();
    private readonly HashSet<string> reviewIds = new HashSet<string>();
    private readonly Dictionary<string, int> mistakesByCounty = new Dictionary<string, int>();
    private readonly Dictionary<string, Material> countyMaterials = new Dictionary<string, Material>();

    private Camera gameCamera;
    private Transform soldier;
    private Transform soldierBody;
    private Transform soldierRightArm;
    private Transform soldierLeftArm;
    private Transform soldierRightLeg;
    private Transform soldierLeftLeg;
    private Transform soldierSword;
    private Transform enemy;
    private Transform enemyBody;
    private Vector3 cameraMapPosition;
    private CountyData currentTarget;
    private CountyData playerCounty;
    private int queueIndex;
    private int score;
    private int mistakes;
    private int lives = MaximumLives;
    private int phaseNumber;
    private int battleVariant;
    private bool inBattle;
    private bool gameOver;
    private bool gameFinished;
    private bool moving;
    private float walkClock;
    private string feedback = "";
    private Color feedbackColor = Color.white;

    private void Start()
    {
        Application.targetFrameRate = 60;
        BuildScene();
        StartNewGame();
    }

    private void Update()
    {
        if (gameOver || gameFinished || inBattle)
            return;

        float horizontal = Input.GetAxisRaw("Horizontal");
        float vertical = Input.GetAxisRaw("Vertical");
        Vector3 input = new Vector3(horizontal, 0f, vertical);
        moving = input.sqrMagnitude > 0.01f;
        if (input.sqrMagnitude > 1f)
            input.Normalize();

        soldier.position += input * (4.8f * Time.deltaTime);
        soldier.position = new Vector3(
            Mathf.Clamp(soldier.position.x, -15.5f, 15.5f),
            BlockHeight,
            Mathf.Clamp(soldier.position.z, -9.5f, 9.5f));

        if (moving)
        {
            walkClock += Time.deltaTime * 10f;
            soldier.rotation = Quaternion.Slerp(
                soldier.rotation,
                Quaternion.LookRotation(input, Vector3.up),
                Time.deltaTime * 12f);
            soldierRightArm.localRotation = Quaternion.Euler(Mathf.Sin(walkClock) * 34f, 0f, 0f);
            soldierLeftArm.localRotation = Quaternion.Euler(-Mathf.Sin(walkClock) * 34f, 0f, 0f);
            soldierRightLeg.localRotation = Quaternion.Euler(-Mathf.Sin(walkClock) * 30f, 0f, 0f);
            soldierLeftLeg.localRotation = Quaternion.Euler(Mathf.Sin(walkClock) * 30f, 0f, 0f);
        }
        else
        {
            ResetWalkPose();
        }

        playerCounty = FindCountyAtWorld(soldier.position);
        if (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter))
            ConfirmCounty();
    }

    private void LateUpdate()
    {
        if (gameCamera == null)
            return;

        if (!inBattle)
        {
            gameCamera.transform.position = Vector3.Lerp(
                gameCamera.transform.position,
                cameraMapPosition,
                Time.deltaTime * 2.2f);
            gameCamera.transform.rotation = Quaternion.Slerp(
                gameCamera.transform.rotation,
                Quaternion.Euler(55f, 0f, 0f),
                Time.deltaTime * 2f);
        }
    }

    private void BuildScene()
    {
        TextAsset mapData = Resources.Load<TextAsset>("counties");
        if (mapData == null)
            throw new InvalidOperationException("The county map resource could not be loaded.");
        CountyDataFile data = JsonUtility.FromJson<CountyDataFile>(mapData.text);
        if (data == null || data.counties == null || data.counties.Length != 19)
            throw new InvalidOperationException("The county map must contain exactly 19 counties.");
        counties.AddRange(data.counties);

        RenderSettings.ambientLight = new Color(0.72f, 0.77f, 0.82f);
        RenderSettings.fog = true;
        RenderSettings.fogColor = new Color(0.67f, 0.77f, 0.80f);
        RenderSettings.fogDensity = 0.008f;

        Material board = MakeMaterial(new Color(0.29f, 0.48f, 0.34f));
        CreateCube("Meadow", new Vector3(0f, -0.13f, 0f), new Vector3(34f, 0.2f, 21f), board, transform);
        Material borderMaterial = MakeMaterial(new Color(0.91f, 0.86f, 0.66f));
        for (int i = 0; i < counties.Count; i++)
        {
            Material material = MakeMaterial(CountyPalette[i % CountyPalette.Length]);
            countyMaterials.Add(counties[i].id, material);
            BuildVoxelCounty(counties[i], material, borderMaterial);
        }

        BuildScenery();
        BuildSoldier();
        BuildCamera();
        BuildLighting();
    }

    private void BuildVoxelCounty(CountyData county, Material material, Material borderMaterial)
    {
        if (county.points == null || county.points.Length < 6 || county.points.Length % 2 != 0)
            throw new InvalidOperationException("Invalid boundary for county " + county.id);

        float minX = float.MaxValue;
        float maxX = float.MinValue;
        float minY = float.MaxValue;
        float maxY = float.MinValue;
        for (int i = 0; i < county.points.Length; i += 2)
        {
            minX = Mathf.Min(minX, county.points[i]);
            maxX = Mathf.Max(maxX, county.points[i]);
            minY = Mathf.Min(minY, county.points[i + 1]);
            maxY = Mathf.Max(maxY, county.points[i + 1]);
        }
        minX = Mathf.Floor(minX / GridStep) * GridStep;
        minY = Mathf.Floor(minY / GridStep) * GridStep;

        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        float halfBlock = GridStep * MapScale * 0.46f;
        for (float y = minY; y <= maxY; y += GridStep)
        {
            for (float x = minX; x <= maxX; x += GridStep)
            {
                float centerX = x + GridStep * 0.5f;
                float centerY = y + GridStep * 0.5f;
                if (!PointInPolygon(centerX, centerY, county.points))
                    continue;

                AddVoxelCube(
                    vertices,
                    triangles,
                    MapPointToWorld(centerX, centerY) + Vector3.up * (BlockHeight * 0.5f),
                    new Vector3(halfBlock, BlockHeight * 0.5f, halfBlock));
            }
        }

        if (vertices.Count == 0)
            throw new InvalidOperationException("No voxel blocks generated for county " + county.name);

        var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        var countyObject = new GameObject("County_" + county.id);
        countyObject.transform.SetParent(transform, true);
        countyObject.AddComponent<MeshFilter>().sharedMesh = mesh;
        countyObject.AddComponent<MeshRenderer>().sharedMaterial = material;

        var lineObject = new GameObject("Border_" + county.id);
        lineObject.transform.SetParent(transform, false);
        var line = lineObject.AddComponent<LineRenderer>();
        line.useWorldSpace = true;
        line.loop = true;
        line.positionCount = county.points.Length / 2;
        line.startWidth = 0.045f;
        line.endWidth = 0.045f;
        line.sharedMaterial = borderMaterial;
        for (int i = 0; i < line.positionCount; i++)
            line.SetPosition(i, MapPointToWorld(county.points[i * 2], county.points[i * 2 + 1]) + Vector3.up * (BlockHeight + 0.025f));
    }

    private void BuildScenery()
    {
        Material trunk = MakeMaterial(new Color(0.40f, 0.28f, 0.18f));
        Material leaves = MakeMaterial(new Color(0.22f, 0.48f, 0.28f));
        for (int i = 0; i < 16; i++)
        {
            float angle = i * Mathf.PI * 2f / 16f;
            Vector3 position = new Vector3(Mathf.Cos(angle) * 16.4f, 0f, Mathf.Sin(angle) * 9.7f);
            CreateCube("VoxelTreeTrunk", position + Vector3.up * 0.45f, new Vector3(0.32f, 0.9f, 0.32f), trunk, transform);
            CreateCube("VoxelTreeCanopy", position + Vector3.up * 1.25f, new Vector3(1.05f, 0.9f, 1.05f), leaves, transform);
        }
    }

    private void BuildSoldier()
    {
        soldier = new GameObject("VoxelSoldier").transform;
        soldier.SetParent(transform, false);
        soldierBody = CreateCube("Uniform", new Vector3(0f, 0.76f, 0f), new Vector3(0.48f, 0.63f, 0.34f), MakeMaterial(SoldierGreen), soldier).transform;
        CreateCube("Helmet", new Vector3(0f, 1.27f, 0f), new Vector3(0.47f, 0.26f, 0.43f), MakeMaterial(new Color(0.48f, 0.57f, 0.29f)), soldier);
        CreateCube("Face", new Vector3(0f, 1.06f, -0.02f), new Vector3(0.3f, 0.27f, 0.28f), MakeMaterial(new Color(0.79f, 0.62f, 0.47f)), soldier);
        CreateCube("Backpack", new Vector3(0f, 0.78f, 0.25f), new Vector3(0.4f, 0.45f, 0.2f), MakeMaterial(new Color(0.42f, 0.31f, 0.18f)), soldier);

        soldierLeftArm = MakeLimb("LeftArm", new Vector3(-0.31f, 0.95f, 0f), new Vector3(0.19f, 0.47f, 0.2f), SoldierGreen, soldier);
        soldierRightArm = MakeLimb("RightArm", new Vector3(0.31f, 0.95f, 0f), new Vector3(0.19f, 0.47f, 0.2f), SoldierGreen, soldier);
        soldierLeftLeg = MakeLimb("LeftLeg", new Vector3(-0.14f, 0.28f, 0f), new Vector3(0.2f, 0.48f, 0.22f), new Color(0.25f, 0.29f, 0.19f), soldier);
        soldierRightLeg = MakeLimb("RightLeg", new Vector3(0.14f, 0.28f, 0f), new Vector3(0.2f, 0.48f, 0.22f), new Color(0.25f, 0.29f, 0.19f), soldier);
        soldierSword = CreateCube("Sword", new Vector3(0.34f, 0.84f, -0.04f), new Vector3(0.09f, 0.66f, 0.09f), MakeMaterial(new Color(0.78f, 0.84f, 0.82f)), soldier).transform;
    }

    private void BuildCamera()
    {
        var cameraObject = new GameObject("GameCamera");
        gameCamera = cameraObject.AddComponent<Camera>();
        gameCamera.orthographic = true;
        gameCamera.orthographicSize = 12f;
        cameraMapPosition = new Vector3(0f, 24f, -18f);
        gameCamera.transform.position = cameraMapPosition;
        gameCamera.transform.rotation = Quaternion.Euler(55f, 0f, 0f);
        gameCamera.clearFlags = CameraClearFlags.SolidColor;
        gameCamera.backgroundColor = new Color(0.48f, 0.65f, 0.72f);
    }

    private void BuildLighting()
    {
        var lightObject = new GameObject("VoxelSun");
        var light = lightObject.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 1.25f;
        light.shadows = LightShadows.Soft;
        light.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
    }

    private void StartNewGame()
    {
        learned.Clear();
        reviewIds.Clear();
        mistakesByCounty.Clear();
        for (int i = 0; i < counties.Count; i++)
            countyMaterials[counties[i].id].color = CountyPalette[i % CountyPalette.Length];
        roundQueue.Clear();
        roundQueue.AddRange(counties);
        Shuffle(roundQueue);
        queueIndex = 0;
        score = 0;
        mistakes = 0;
        lives = MaximumLives;
        phaseNumber = 0;
        gameOver = false;
        gameFinished = false;
        inBattle = false;
        feedback = "Keresd meg a megadott vármegyét, majd nyomj Entert!";
        feedbackColor = Color.white;
        playerCounty = null;
        soldier.localScale = Vector3.one;
        soldier.rotation = Quaternion.identity;
        soldierSword.localRotation = Quaternion.identity;
        soldierBody.localPosition = new Vector3(0f, 0.76f, 0f);
        soldier.position = Vector3.up * BlockHeight;
        ResetWalkPose();
        CountyData startingCounty = counties[UnityEngine.Random.Range(0, counties.Count)];
        soldier.position = MapPointToWorld(startingCounty.seat_x, startingCounty.seat_y) + Vector3.up * BlockHeight;
        NextTarget();
    }

    private void NextTarget()
    {
        if (queueIndex >= roundQueue.Count)
        {
            if (phaseNumber == 0 && reviewIds.Count > 0 && lives > 0)
            {
                phaseNumber = 1;
                roundQueue.Clear();
                foreach (CountyData county in counties)
                {
                    if (reviewIds.Contains(county.id) && !learned.Contains(county.id))
                        roundQueue.Add(county);
                }
                Shuffle(roundQueue);
                queueIndex = 0;
            }
            else if (phaseNumber == 1 && reviewIds.Count > 0 && lives > 0)
            {
                roundQueue.Clear();
                foreach (CountyData county in counties)
                {
                    if (reviewIds.Contains(county.id) && !learned.Contains(county.id))
                        roundQueue.Add(county);
                }
                Shuffle(roundQueue);
                queueIndex = 0;
            }
            else
            {
                gameFinished = true;
                currentTarget = null;
                feedback = "Minden járőrútvonal teljesítve!";
                feedbackColor = new Color(0.5f, 1f, 0.63f);
                return;
            }
        }

        if (queueIndex < roundQueue.Count)
        {
            currentTarget = roundQueue[queueIndex++];
            feedback = "Vezesd a katonát ide, majd nyomj Entert!";
            feedbackColor = Color.white;
        }
    }

    private void ConfirmCounty()
    {
        if (inBattle || gameOver || gameFinished || currentTarget == null)
            return;
        playerCounty = FindCountyAtWorld(soldier.position);
        if (playerCounty == null)
        {
            feedback = "Lépj be egy vármegyébe, aztán nyomj Entert!";
            feedbackColor = new Color(1f, 0.79f, 0.4f);
            return;
        }
        StartCoroutine(Battle(playerCounty.id == currentTarget.id));
    }

    private IEnumerator Battle(bool victory)
    {
        inBattle = true;
        bool finalBlow = false;
        battleVariant = UnityEngine.Random.Range(0, 3);
        int enemyIndex = UnityEngine.Random.Range(0, EnemyNames.Length);
        enemy = BuildEnemy(enemyIndex);

        Vector3 startPosition = gameCamera.transform.position;
        Quaternion startRotation = gameCamera.transform.rotation;
        Vector3 battlePosition = soldier.position + new Vector3(0f, 8.5f, -7f);
        Quaternion battleRotation = Quaternion.LookRotation(soldier.position + Vector3.up - battlePosition);
        yield return AnimateCamera(startPosition, battlePosition, startRotation, battleRotation, 0.55f, 5f);

        if (victory)
        {
            feedback = "GYŐZELEM! " + EnemyNames[enemyIndex] + " legyőzve.";
            feedbackColor = new Color(0.52f, 1f, 0.61f);
            yield return AnimateVictory();
            learned.Add(currentTarget.id);
            reviewIds.Remove(currentTarget.id);
            countyMaterials[currentTarget.id].color = LearnedColor;
            score++;
            Destroy(enemy.gameObject);
            enemy = null;
            NextTarget();
        }
        else
        {
            mistakes++;
            lives--;
            if (!mistakesByCounty.ContainsKey(currentTarget.id))
                mistakesByCounty[currentTarget.id] = 0;
            mistakesByCounty[currentTarget.id]++;
            reviewIds.Add(currentTarget.id);
            feedback = lives > 0
                ? "Sérülés! " + EnemyNames[enemyIndex] + " győzött. Maradt " + lives + " életed."
                : "JÁTÉK VÉGE! " + EnemyNames[enemyIndex] + " legyőzte a katonát.";
            feedbackColor = new Color(1f, 0.57f, 0.43f);
            yield return AnimateDefeat(lives == 0);
            Destroy(enemy.gameObject);
            enemy = null;
            if (lives == 0)
                finalBlow = true;
        }

        yield return AnimateCamera(
            gameCamera.transform.position,
            cameraMapPosition,
            gameCamera.transform.rotation,
            Quaternion.Euler(55f, 0f, 0f),
            0.5f,
            12f);
        inBattle = false;
        if (finalBlow)
            gameOver = true;
    }

    private IEnumerator AnimateCamera(
        Vector3 fromPosition,
        Vector3 toPosition,
        Quaternion fromRotation,
        Quaternion toRotation,
        float duration,
        float targetSize)
    {
        float elapsed = 0f;
        float startSize = gameCamera.orthographicSize;
        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(elapsed / duration));
            gameCamera.transform.position = Vector3.Lerp(fromPosition, toPosition, t);
            gameCamera.transform.rotation = Quaternion.Slerp(fromRotation, toRotation, t);
            gameCamera.orthographicSize = Mathf.Lerp(startSize, targetSize, t);
            yield return null;
        }
        gameCamera.orthographicSize = targetSize;
        yield return new WaitForSeconds(0.45f);
    }

    private IEnumerator AnimateVictory()
    {
        switch (battleVariant)
        {
            case 0:
                yield return SwingSword(-100f, 110f);
                enemyBody.localRotation = Quaternion.Euler(0f, 0f, 72f);
                break;
            case 1:
                soldierBody.localPosition += Vector3.up * 0.55f;
                yield return SwingSword(-140f, 155f);
                soldierBody.localPosition -= Vector3.up * 0.55f;
                enemy.localPosition += Vector3.right * 0.8f;
                break;
            default:
                yield return SwingSword(-170f, 180f);
                soldier.rotation *= Quaternion.Euler(0f, 180f, 0f);
                enemy.localScale = Vector3.one * 0.7f;
                break;
        }
        yield return new WaitForSeconds(0.35f);
        soldier.rotation = Quaternion.identity;
        soldierBody.localPosition = new Vector3(0f, 0.76f, 0f);
    }

    private IEnumerator AnimateDefeat(bool finalBlow)
    {
        switch (battleVariant)
        {
            case 0:
                enemy.localPosition += Vector3.left * 0.35f;
                soldier.localRotation = Quaternion.Euler(0f, 0f, 48f);
                break;
            case 1:
                soldierRightArm.localRotation = Quaternion.Euler(0f, 0f, -55f);
                soldier.localRotation = Quaternion.Euler(32f, 0f, -28f);
                break;
            default:
                enemy.localScale = Vector3.one * 1.15f;
                soldierSword.localRotation = Quaternion.Euler(0f, 0f, 65f);
                soldier.localRotation = Quaternion.Euler(0f, 0f, 62f);
                break;
        }

        yield return new WaitForSeconds(finalBlow ? 0.35f : 0.6f);
        if (finalBlow)
        {
            soldier.position += Vector3.down * 0.35f;
            soldier.localScale = new Vector3(1f, 0.72f, 1f);
        }
        else
        {
            soldier.localRotation = Quaternion.identity;
            soldierSword.localRotation = Quaternion.identity;
            soldierRightArm.localRotation = Quaternion.identity;
        }
    }

    private IEnumerator SwingSword(float firstAngle, float secondAngle)
    {
        float elapsed = 0f;
        while (elapsed < 0.28f)
        {
            elapsed += Time.deltaTime;
            soldierSword.localRotation = Quaternion.Euler(0f, 0f, Mathf.Lerp(0f, firstAngle, elapsed / 0.28f));
            yield return null;
        }
        elapsed = 0f;
        while (elapsed < 0.3f)
        {
            elapsed += Time.deltaTime;
            soldierSword.localRotation = Quaternion.Euler(0f, 0f, Mathf.Lerp(firstAngle, secondAngle, elapsed / 0.3f));
            yield return null;
        }
        soldierSword.localRotation = Quaternion.identity;
    }

    private Transform BuildEnemy(int kind)
    {
        var root = new GameObject("VoxelEnemy_" + EnemyNames[kind]).transform;
        root.position = soldier.position + new Vector3(1.15f, 0f, 0f);
        root.rotation = Quaternion.Euler(0f, -90f, 0f);
        Material color = MakeMaterial(EnemyColors[kind]);
        enemyBody = CreateCube("EnemyBody", new Vector3(0f, 0.7f, 0f), new Vector3(0.65f, 0.65f, 0.5f), color, root).transform;
        CreateCube("EnemyHead", new Vector3(0f, 1.25f, -0.03f), new Vector3(0.62f, 0.45f, 0.52f), MakeMaterial(EnemyColors[kind] * 1.18f), root);
        if (kind == 0)
        {
            CreateCube("Helmet", new Vector3(0f, 1.52f, 0f), new Vector3(0.72f, 0.22f, 0.62f), MakeMaterial(new Color(0.72f, 0.53f, 0.25f)), root);
            CreateCube("EnemySword", new Vector3(-0.44f, 0.85f, 0f), new Vector3(0.1f, 0.8f, 0.1f), MakeMaterial(Color.gray), root);
        }
        else if (kind == 1)
        {
            CreateCube("TuskL", new Vector3(-0.24f, 1.18f, -0.29f), new Vector3(0.13f, 0.26f, 0.14f), MakeMaterial(Color.white), root);
            CreateCube("TuskR", new Vector3(0.24f, 1.18f, -0.29f), new Vector3(0.13f, 0.26f, 0.14f), MakeMaterial(Color.white), root);
        }
        else
        {
            CreateCube("DragonWingL", new Vector3(-0.48f, 0.93f, 0.2f), new Vector3(0.78f, 0.12f, 0.5f), MakeMaterial(EnemyColors[kind] * 0.8f), root);
            CreateCube("DragonWingR", new Vector3(0.48f, 0.93f, 0.2f), new Vector3(0.78f, 0.12f, 0.5f), MakeMaterial(EnemyColors[kind] * 0.8f), root);
            CreateCube("DragonHorn", new Vector3(0f, 1.64f, 0f), new Vector3(0.14f, 0.28f, 0.14f), MakeMaterial(new Color(0.9f, 0.73f, 0.35f)), root);
        }
        return root;
    }

    private void OnGUI()
    {
        DrawPanel(new Rect(22f, 22f, 390f, 160f), new Color(0.11f, 0.20f, 0.17f, 0.94f));
        DrawLabel(new Rect(42f, 36f, 350f, 27f), "MEGYÉRŐL MEGYÉRE · VOXEL JÁRŐR", 17, new Color(0.78f, 0.87f, 0.67f), FontStyle.Bold);
        DrawLabel(new Rect(42f, 68f, 350f, 36f), currentTarget == null ? "Járőrút teljesítve" : "Cél: " + currentTarget.name, 25, Color.white, FontStyle.Bold);
        DrawLabel(new Rect(42f, 111f, 350f, 25f), "Kör " + (phaseNumber == 0 ? "alap" : "tanuló") + "  ·  " + score + " pont", 17, new Color(0.91f, 0.84f, 0.64f), FontStyle.Normal);
        DrawLabel(new Rect(42f, 143f, 350f, 25f), "Élet: " + lives + " / " + MaximumLives + "    Hibák: " + mistakes, 16, new Color(1f, 0.76f, 0.60f), FontStyle.Bold);

        DrawPanel(new Rect(Screen.width - 372f, 22f, 350f, 78f), new Color(0.11f, 0.20f, 0.17f, 0.94f));
        DrawLabel(new Rect(Screen.width - 352f, 32f, 310f, 58f), "MOZGÁS  ·  WASD / NYILAK\nVÁLASZTÁS  ·  ENTER", 16, Color.white, FontStyle.Bold);

        if (!string.IsNullOrEmpty(feedback))
        {
            DrawPanel(new Rect(Screen.width * 0.5f - 310f, Screen.height - 98f, 620f, 72f), new Color(0.11f, 0.20f, 0.17f, 0.96f));
            DrawLabel(new Rect(Screen.width * 0.5f - 285f, Screen.height - 82f, 570f, 44f), feedback, 19, feedbackColor, FontStyle.Bold);
        }

        if (gameOver || gameFinished)
        {
            DrawPanel(new Rect(Screen.width * 0.5f - 300f, Screen.height * 0.5f - 155f, 600f, 310f), new Color(0.09f, 0.16f, 0.14f, 0.97f));
            DrawLabel(new Rect(Screen.width * 0.5f - 265f, Screen.height * 0.5f - 132f, 530f, 48f), gameOver ? "JÁTÉK VÉGE" : "JÁRŐRÚT TELJESÍTVE", 30, Color.white, FontStyle.Bold);
            DrawLabel(new Rect(Screen.width * 0.5f - 265f, Screen.height * 0.5f - 78f, 530f, 36f), score + " pont · " + mistakes + " hibás válasz", 19, new Color(0.92f, 0.82f, 0.62f), FontStyle.Normal);
            DrawLabel(new Rect(Screen.width * 0.5f - 265f, Screen.height * 0.5f - 35f, 530f, 68f), BuildReviewSummary(), 16, new Color(0.98f, 0.84f, 0.73f), FontStyle.Normal);
            if (GUI.Button(new Rect(Screen.width * 0.5f - 115f, Screen.height * 0.5f + 76f, 230f, 48f), "ÚJ JÁTÉK"))
                StartNewGame();
        }
    }

    private void DrawPanel(Rect rect, Color color)
    {
        Color previous = GUI.color;
        GUI.color = color;
        GUI.DrawTexture(rect, Texture2D.whiteTexture);
        GUI.color = previous;
    }

    private void DrawLabel(Rect rect, string text, int size, Color color, FontStyle style)
    {
        var guiStyle = new GUIStyle(GUI.skin.label)
        {
            fontSize = size,
            fontStyle = style,
            wordWrap = true,
            alignment = TextAnchor.MiddleLeft
        };
        guiStyle.normal.textColor = color;
        GUI.Label(rect, text, guiStyle);
    }

    private string BuildReviewSummary()
    {
        var names = new List<string>();
        foreach (CountyData county in counties)
        {
            if (reviewIds.Contains(county.id))
                names.Add(county.name + " (" + mistakesByCounty[county.id] + ")");
        }
        return names.Count == 0 ? "Nem maradt elhibázott vármegye." : "Még tanulandó: " + string.Join(", ", names);
    }

    private CountyData FindCountyAtWorld(Vector3 position)
    {
        float x = position.x / MapScale + MapCenterX;
        float y = MapCenterY - position.z / MapScale;
        foreach (CountyData county in counties)
        {
            if (PointInPolygon(x, y, county.points))
                return county;
        }
        return null;
    }

    private static bool PointInPolygon(float x, float y, float[] points)
    {
        bool inside = false;
        int count = points.Length / 2;
        for (int i = 0, j = count - 1; i < count; j = i++)
        {
            float xi = points[i * 2];
            float yi = points[i * 2 + 1];
            float xj = points[j * 2];
            float yj = points[j * 2 + 1];
            bool crosses = ((yi > y) != (yj > y))
                && (x < (xj - xi) * (y - yi) / ((yj - yi) == 0f ? 0.0001f : (yj - yi)) + xi);
            if (crosses)
                inside = !inside;
        }
        return inside;
    }

    private static Vector3 MapPointToWorld(float x, float y)
    {
        return new Vector3((x - MapCenterX) * MapScale, 0f, (MapCenterY - y) * MapScale);
    }

    private static void AddVoxelCube(
        List<Vector3> vertices,
        List<int> triangles,
        Vector3 center,
        Vector3 halfSize)
    {
        Vector3[] corners =
        {
            center + new Vector3(-halfSize.x, -halfSize.y, -halfSize.z),
            center + new Vector3(halfSize.x, -halfSize.y, -halfSize.z),
            center + new Vector3(halfSize.x, -halfSize.y, halfSize.z),
            center + new Vector3(-halfSize.x, -halfSize.y, halfSize.z),
            center + new Vector3(-halfSize.x, halfSize.y, -halfSize.z),
            center + new Vector3(halfSize.x, halfSize.y, -halfSize.z),
            center + new Vector3(halfSize.x, halfSize.y, halfSize.z),
            center + new Vector3(-halfSize.x, halfSize.y, halfSize.z)
        };
        int[,] faces =
        {
            { 0, 1, 2, 3 },
            { 4, 7, 6, 5 },
            { 0, 4, 5, 1 },
            { 3, 2, 6, 7 },
            { 0, 3, 7, 4 },
            { 1, 5, 6, 2 }
        };

        for (int face = 0; face < 6; face++)
        {
            int faceStart = vertices.Count;
            for (int corner = 0; corner < 4; corner++)
                vertices.Add(corners[faces[face, corner]]);
            triangles.Add(faceStart);
            triangles.Add(faceStart + 1);
            triangles.Add(faceStart + 2);
            triangles.Add(faceStart);
            triangles.Add(faceStart + 2);
            triangles.Add(faceStart + 3);
        }
    }

    private static Transform MakeLimb(string name, Vector3 position, Vector3 scale, Color color, Transform parent)
    {
        var pivot = new GameObject(name).transform;
        pivot.SetParent(parent, false);
        pivot.localPosition = position;
        CreateCube(name + "Block", new Vector3(0f, -scale.y * 0.35f, 0f), scale, MakeMaterial(color), pivot);
        return pivot;
    }

    private static GameObject CreateCube(string name, Vector3 position, Vector3 scale, Material material, Transform parent)
    {
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube.name = name;
        cube.transform.SetParent(parent, false);
        cube.transform.localPosition = position;
        cube.transform.localScale = scale;
        cube.GetComponent<Renderer>().sharedMaterial = material;
        Collider collider = cube.GetComponent<Collider>();
        if (collider != null)
            Destroy(collider);
        return cube;
    }

    private static Material MakeMaterial(Color color)
    {
        if (voxelShader == null)
            voxelShader = Resources.Load<Shader>("VoxelColor");
        if (voxelShader == null)
            throw new InvalidOperationException("The voxel color shader resource could not be loaded.");
        return new Material(voxelShader) { color = color };
    }

    private static void Shuffle<T>(IList<T> list)
    {
        for (int i = list.Count - 1; i > 0; i--)
        {
            int j = UnityEngine.Random.Range(0, i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }

    private void ResetWalkPose()
    {
        soldierRightArm.localRotation = Quaternion.Slerp(soldierRightArm.localRotation, Quaternion.identity, Time.deltaTime * 8f);
        soldierLeftArm.localRotation = Quaternion.Slerp(soldierLeftArm.localRotation, Quaternion.identity, Time.deltaTime * 8f);
        soldierRightLeg.localRotation = Quaternion.Slerp(soldierRightLeg.localRotation, Quaternion.identity, Time.deltaTime * 8f);
        soldierLeftLeg.localRotation = Quaternion.Slerp(soldierLeftLeg.localRotation, Quaternion.identity, Time.deltaTime * 8f);
    }
}
