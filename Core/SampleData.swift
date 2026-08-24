import Foundation

public enum SampleData {
    public static let miniProteinPDB = """
    HEADER    MOLECULEPAD SAMPLE
    ATOM      1  N   ALA A   1      -5.100   0.200   0.000  1.00 20.00           N
    ATOM      2  CA  ALA A   1      -3.700   0.000   0.200  1.00 18.00           C
    ATOM      3  C   ALA A   1      -3.100   1.250   0.850  1.00 17.00           C
    ATOM      4  O   ALA A   1      -3.650   2.350   0.720  1.00 19.00           O
    ATOM      5  CB  ALA A   1      -3.100  -1.250   0.850  1.00 22.00           C
    ATOM      6  N   GLY A   2      -1.950   1.050   1.500  1.00 16.00           N
    ATOM      7  CA  GLY A   2      -1.220   2.170   2.080  1.00 15.00           C
    ATOM      8  C   GLY A   2       0.210   1.780   2.420  1.00 14.00           C
    ATOM      9  O   GLY A   2       0.590   0.610   2.430  1.00 18.00           O
    ATOM     10  N   SER A   3       1.020   2.780   2.750  1.00 15.00           N
    ATOM     11  CA  SER A   3       2.410   2.530   3.100  1.00 13.00           C
    ATOM     12  C   SER A   3       3.270   2.250   1.880  1.00 14.00           C
    ATOM     13  O   SER A   3       2.850   2.520   0.760  1.00 17.00           O
    ATOM     14  CB  SER A   3       2.940   1.420   4.020  1.00 20.00           C
    ATOM     15  OG  SER A   3       2.180   1.280   5.180  1.00 24.00           O
    ATOM     16  N   LYS A   4       4.490   1.690   2.100  1.00 15.00           N
    ATOM     17  CA  LYS A   4       5.390   1.330   1.020  1.00 14.00           C
    ATOM     18  C   LYS A   4       5.100  -0.050   0.430  1.00 15.00           C
    ATOM     19  O   LYS A   4       5.250  -1.080   1.090  1.00 18.00           O
    ATOM     20  CB  LYS A   4       6.830   1.390   1.560  1.00 19.00           C
    END
    """

    public static var miniProtein: MolecularStructure {
        // The bundled data is fixed and validated by tests.
        try! PDBParser().parse(miniProteinPDB, name: "Welcome protein")
    }
}
